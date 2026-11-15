//
//  StreamAudioEngine.swift
//  DailyFlo
//
//  Streams a meditation track from the private Supabase Storage `meditations`
//  bucket. Mirrors FileAudioEngine's surface (play / pause / resume / stop)
//  so MeditationAudioController can treat bundled and streamed sources alike.
//
//  The DB stores `audio_path` as "<bucket>/<key…>" (e.g.
//  "meditations/mist-10.m4a"): first path component is the bucket, the rest is
//  the object key. We sign a URL (session length + 30 min, min 1 hour), stream
//  it on an AVQueuePlayer looped by AVPlayerLooper (so a 10-min track fills a
//  60-min session seamlessly), and fade volume the same way FileAudioEngine
//  does. If signing/loading fails — or playback simply never starts within a
//  few seconds — `onFailure` fires exactly once so the controller falls back to
//  the bundled loop / synth. A slot is never left silent.
//

import AVFoundation
import Supabase

@MainActor
final class StreamAudioEngine {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var looperStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    private let targetVolume: Float = 0.85
    /// Fall back if real playback hasn't begun within this long of `play(path:)`.
    private let startTimeoutSeconds: Double = 8

    /// Desired play/pause intent, honoured once playback is possible — covers a
    /// pause issued during the signing/loading window.
    private var shouldBePlaying = true
    /// Guards against teardown-after-stop and double `onFailure`.
    private var isStopped = false
    private var didFail = false
    /// True once the queue has actually reached `.playing`.
    private var hasStarted = false

    /// Called once if signing/loading fails or playback never starts.
    private var onFailure: (() -> Void)?
    private var streamURL: URL?
    private var startTimeoutTask: Task<Void, Never>?

    /// Signs `path`, streams it looped, and fades in. `onFailure` is called at
    /// most once, on the main actor, if anything goes wrong. `duration` sets the
    /// signed-URL lifetime so a long session can't outlive its URL.
    func play(path: String, duration: MeditationDuration, onFailure: @escaping () -> Void) {
        self.onFailure = onFailure
        scheduleStartTimeout()

        guard let (bucket, key) = Self.split(path) else {
            #if DEBUG
            print("StreamAudioEngine: malformed audio_path '\(path)' — expected '<bucket>/<key>'")
            #endif
            fail()
            return
        }

        // Session length + 30 min, floored at 1 hour, so a 60-min session still
        // has a valid URL at the end.
        let ttl = max(3600, duration.seconds + 1800)

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await SupabaseClient.shared.storage
                    .from(bucket)
                    .createSignedURL(path: key, expiresIn: ttl)
                guard !self.isStopped else { return }
                self.start(url: url)
            } catch {
                #if DEBUG
                print("StreamAudioEngine: signing failed for '\(path)': \(error)")
                #endif
                self.fail()
            }
        }
    }

    private func start(url: URL) {
        streamURL = url
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.volume = 0
        // AVPlayerLooper enqueues COPIES of the template item into the queue and
        // keeps the loop gapless; the template item itself is never played, so
        // its own status stays .unknown — which is why readiness/failure must
        // come from the looper and the queue, not the template item.
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        self.looper = looper
        self.player = queue

        // Failure comes from the looper.
        looperStatusObservation = looper.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let failed = observed.status == .failed
            let errorDescription = observed.error.map { String(describing: $0) }
            Task { @MainActor [weak self] in
                if failed { self?.handleLooperFailed(errorDescription) }
            }
        }

        // Readiness = the queue actually reaching `.playing`. The fade-in and the
        // start-timeout cancellation hang off that, so we only commit once audio
        // is genuinely flowing.
        timeControlObservation = queue.observe(\.timeControlStatus, options: [.new]) { [weak self] observed, _ in
            let isPlaying = observed.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                if isPlaying { self?.handlePlaybackStarted() }
            }
        }

        // Kick playback off; the queue begins as soon as its item is ready.
        if shouldBePlaying { queue.play() }
    }

    private func handlePlaybackStarted() {
        guard !isStopped else { return }
        if !hasStarted {
            hasStarted = true
            cancelStartTimeout()
            #if DEBUG
            print("StreamAudioEngine: streaming '\(streamURL?.lastPathComponent ?? "?")' from Storage")
            #endif
        }
        guard shouldBePlaying else { return }
        fade(to: targetVolume, duration: 2.0)
    }

    private func handleLooperFailed(_ errorDescription: String?) {
        guard !isStopped else { return }
        #if DEBUG
        print("StreamAudioEngine: looper failed to load: \(errorDescription ?? "unknown")")
        #endif
        fail()
    }

    func pause() {
        shouldBePlaying = false
        guard let player, player.rate != 0 else { return }
        fade(to: 0, duration: 0.5) { [weak self] in
            self?.player?.pause()
        }
    }

    func resume() {
        shouldBePlaying = true
        guard let player else { return }
        player.play()
        fade(to: targetVolume, duration: 1.0)
    }

    func stop(fade duration: Double = 1.0) {
        guard let player, !isStopped else {
            teardown()
            return
        }
        fade(to: 0, duration: duration) { [weak self] in
            player.pause()
            self?.teardown()
        }
    }

    // MARK: - Start timeout (never-silent guarantee)

    /// Falls back to bundled/synth if real playback hasn't begun within
    /// `startTimeoutSeconds`. Cancelled once audio is playing or on stop.
    private func scheduleStartTimeout() {
        cancelStartTimeout()
        startTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.startTimeoutSeconds ?? 8) * 1_000_000_000))
            guard let self, !Task.isCancelled,
                  !self.isStopped, !self.hasStarted, !self.didFail, self.shouldBePlaying else { return }
            #if DEBUG
            print("StreamAudioEngine: playback didn't start within \(self.startTimeoutSeconds)s; falling back")
            #endif
            self.fail()
        }
    }

    private func cancelStartTimeout() {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    // MARK: - Internals

    /// Reports a one-time failure and tears down so the controller can fall back.
    private func fail() {
        guard !didFail else { return }
        didFail = true
        let callback = onFailure
        teardown()
        callback?()
    }

    private func teardown() {
        isStopped = true
        cancelStartTimeout()
        looperStatusObservation?.invalidate()
        looperStatusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        onFailure = nil
    }

    /// Ramps `player.volume` toward `target`, matching FileAudioEngine's feel.
    private func fade(to target: Float, duration: Double, completion: (() -> Void)? = nil) {
        guard let player else {
            completion?()
            return
        }

        let steps = 30
        let interval = max(duration / Double(steps), 0.01)
        let start = player.volume
        let delta = (target - start) / Float(steps)

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) { [weak self] in
                guard let self, let player = self.player else { return }
                if i == steps {
                    player.volume = target
                    completion?()
                } else {
                    player.volume = start + delta * Float(i)
                }
            }
        }
    }

    /// Splits "<bucket>/<key…>" into (bucket, key). Returns nil if either side
    /// is missing. The key keeps any nested path (split on the FIRST slash).
    static func split(_ path: String) -> (bucket: String, key: String)? {
        let parts = path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }
}
