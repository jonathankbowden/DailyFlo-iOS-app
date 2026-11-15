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
//  the object key. We sign a 1-hour URL, stream it on an AVQueuePlayer looped
//  by AVPlayerLooper (so a 10-min track fills a 60-min session seamlessly), and
//  fade volume the same way FileAudioEngine does. If signing or loading fails,
//  `onFailure` fires exactly once so the controller falls back to the bundled
//  loop / synth — a slot is never left silent.
//

import AVFoundation
import Supabase

@MainActor
final class StreamAudioEngine {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?

    private let targetVolume: Float = 0.85
    private let signedURLTTL = 3600   // 1 hour

    /// Desired play/pause intent, honoured once the item becomes ready — covers
    /// a pause issued during the ~1s signing/loading window.
    private var shouldBePlaying = true
    /// Guards against teardown-after-stop and double `onFailure`.
    private var isStopped = false
    private var didFail = false

    /// Called once if signing/loading fails, so the controller can fall back.
    private var onFailure: (() -> Void)?
    private var streamURL: URL?

    /// Signs `path`, streams it looped, and fades in. `onFailure` is called at
    /// most once, on the main actor, if anything goes wrong.
    func play(path: String, onFailure: @escaping () -> Void) {
        self.onFailure = onFailure

        guard let (bucket, key) = Self.split(path) else {
            #if DEBUG
            print("StreamAudioEngine: malformed audio_path '\(path)' — expected '<bucket>/<key>'")
            #endif
            fail()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await SupabaseClient.shared.storage
                    .from(bucket)
                    .createSignedURL(path: key, expiresIn: self.signedURLTTL)
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
        // AVPlayerLooper retains the queue + template item and keeps the loop
        // gapless, independent of session length.
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue

        // The KVO callback runs on an arbitrary thread: read Sendable primitives
        // here, then hop to the main actor to touch engine state.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let status = observed.status
            let errorDescription = observed.error.map { String(describing: $0) }
            Task { @MainActor [weak self] in
                self?.handleItemStatus(status, errorDescription: errorDescription)
            }
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, errorDescription: String?) {
        guard !isStopped else { return }
        switch status {
        case .readyToPlay:
            #if DEBUG
            print("StreamAudioEngine: streaming '\(streamURL?.lastPathComponent ?? "?")' from Storage")
            #endif
            if shouldBePlaying {
                player?.play()
                fade(to: targetVolume, duration: 2.0)
            }
        case .failed:
            #if DEBUG
            print("StreamAudioEngine: item failed to load: \(errorDescription ?? "unknown")")
            #endif
            fail()
        default:
            break
        }
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
        statusObservation?.invalidate()
        statusObservation = nil
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
