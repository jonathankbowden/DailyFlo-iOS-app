//
//  MeditationAudioController.swift
//  DailyFlo
//
//  The single owner of meditation playback. Picks one source per slot —
//  a streamed Storage track (StreamAudioEngine), a bundled MP3 loop
//  (FileAudioEngine), or the synthesized AmbientAudioEngine fallback — and
//  never starts more than one at a time. Also owns the shared audio session,
//  the Now Playing lock-screen info, and the remote (play/pause) commands, so
//  playback continues with the screen locked. Exposes the
//  play/pause/resume/stop interface the player view already uses.
//

import AVFoundation
import MediaPlayer
import Observation
import UIKit

@MainActor
@Observable
final class MeditationAudioController {
    private var streamEngine: StreamAudioEngine?
    private var fileEngine: FileAudioEngine?
    private var synthEngine: AmbientAudioEngine?

    private(set) var isPlaying = false

    // Now Playing / lock-screen state for the active session.
    private var currentSession: MeditationSession?
    private var currentDuration: MeditationDuration?
    private var elapsedBase: TimeInterval = 0   // accumulated before the current run
    private var runStart: Date?                 // when the current play/resume began
    private var remoteCommandsWired = false

    /// Begins playback for the given session at the chosen duration. Source
    /// priority **per slot** (theme × duration):
    ///   1. `audioPaths[duration]` → stream the Supabase Storage object.
    ///   2. `audioFileName`        → loop the bundled MP3 via `FileAudioEngine`.
    ///   3. neither                → synthesized `AmbientAudioEngine` fallback.
    /// If streaming fails to sign/load, it falls back to the bundled loop / synth
    /// for the same session — a slot is never left silent. Fire-and-forget.
    func play(session: MeditationSession, duration: MeditationDuration) {
        stop()
        activateSession()
        wireRemoteCommandsIfNeeded()

        currentSession = session
        currentDuration = duration
        elapsedBase = 0
        runStart = Date()

        if let path = session.audioPaths[duration], !path.isEmpty {
            let engine = StreamAudioEngine()
            streamEngine = engine
            engine.play(path: path, duration: duration) { [weak self] in
                // Signing/loading failed — drop to the bundled loop / synth.
                guard let self, self.streamEngine === engine else { return }
                #if DEBUG
                print("MeditationAudioController: stream failed for '\(session.title)'; falling back to bundled/synth")
                #endif
                self.streamEngine = nil
                self.startBundledOrSynth(session)
            }
        } else {
            startBundledOrSynth(session)
        }

        isPlaying = true
        updateNowPlaying(rate: 1)
    }

    /// Bundled MP3 loop if present, otherwise the synthesized fallback.
    private func startBundledOrSynth(_ session: MeditationSession) {
        if let filename = session.audioFileName {
            let engine = FileAudioEngine()
            engine.play(resource: filename)
            fileEngine = engine
        } else {
            #if DEBUG
            print("MeditationAudioController: synth start '\(session.title)' (sound: \(session.ambientSound.rawValue))")
            #endif
            let engine = AmbientAudioEngine()
            do {
                try engine.play(sound: session.ambientSound)
                synthEngine = engine
            } catch {
                #if DEBUG
                print("MeditationAudioController: synth start FAILED for '\(session.title)': \(error)")
                #endif
            }
        }
    }

    func pause() {
        streamEngine?.pause()
        fileEngine?.pause()
        synthEngine?.pause()
        // Freeze accumulated elapsed time at the pause point.
        elapsedBase = currentElapsed()
        runStart = nil
        isPlaying = false
        updateNowPlaying(rate: 0)
    }

    func resume() {
        activateSession()
        streamEngine?.resume()
        fileEngine?.resume()
        synthEngine?.resume()
        runStart = Date()
        isPlaying = true
        updateNowPlaying(rate: 1)
    }

    /// Stops playback with an optional custom fade. Default is the snappy
    /// 1-second fade used when the user explicitly stops (X / dismiss).
    /// A longer fade (3–5s) is appropriate at natural session-end so the
    /// loop bleeds out gently instead of cutting off.
    func stop(fade: Double = 1.0) {
        streamEngine?.stop(fade: fade)
        fileEngine?.stop(fade: fade)
        synthEngine?.stop()
        streamEngine = nil
        fileEngine = nil
        synthEngine = nil
        isPlaying = false
        currentSession = nil
        currentDuration = nil
        runStart = nil
        elapsedBase = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Audio session

    /// Routes audio to `.playback` so it keeps going with the screen locked and
    /// the app in the background (requires UIBackgroundModes = audio). Owned
    /// here so the per-source engines don't each fight over the category.
    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("MeditationAudioController: audio session activation failed: \(error)")
            #endif
        }
    }

    // MARK: - Now Playing (lock screen)

    private func currentElapsed() -> TimeInterval {
        let running = runStart.map { Date().timeIntervalSince($0) } ?? 0
        let total = elapsedBase + running
        if let seconds = currentDuration?.seconds { return min(total, TimeInterval(seconds)) }
        return total
    }

    private func updateNowPlaying(rate: Double) {
        guard let session = currentSession, let duration = currentDuration else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: session.title.capitalized,
            MPMediaItemPropertyArtist: "DailyFLO",
            MPMediaItemPropertyPlaybackDuration: TimeInterval(duration.seconds),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentElapsed(),
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]
        if let image = artworkImage(for: session, duration: duration) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The per-slot background image the card/player showed, for lock-screen art.
    private func artworkImage(for session: MeditationSession, duration: MeditationDuration) -> UIImage? {
        let index: Int
        switch duration {
        case .five: index = 0
        case .ten: index = 1
        case .sixty: index = 2
        }
        let name = session.collectibleImages.indices.contains(index)
            ? session.collectibleImages[index]
            : session.imageName
        return UIImage(named: name)
    }

    // MARK: - Remote commands

    private func wireRemoteCommandsIfNeeded() {
        guard !remoteCommandsWired else { return }
        remoteCommandsWired = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying else { return .commandFailed }
            self.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.pause() } else { self.resume() }
            return .success
        }
    }
}

// MARK: - File-backed engine

/// Loops a bundled audio file with AVAudioPlayer + matching fade behavior
/// so it feels consistent with the synth engine's play/pause/resume/stop.
@MainActor
final class FileAudioEngine {
    private var player: AVAudioPlayer?
    private let targetVolume: Float = 0.85

    /// `resource` is the bundle resource name with or without ".mp3".
    /// Looks up the file in the Meditations/ subdirectory first (preserved
    /// by Xcode's folder-synchronized group) and falls back to a flat
    /// bundle lookup so this keeps working if the bundle layout is ever
    /// flattened.
    func play(resource: String) {
        let base = resource.hasSuffix(".mp3")
            ? String(resource.dropLast(4))
            : resource

        let subdirURL = Bundle.main.url(forResource: base, withExtension: "mp3", subdirectory: "Meditations")
        let flatURL = Bundle.main.url(forResource: base, withExtension: "mp3")
        let url = subdirURL ?? flatURL

        guard let url else {
            #if DEBUG
            print("""
            FileAudioEngine: missing audio resource '\(resource)'
              base name:        \(base)
              bundle path:      \(Bundle.main.bundlePath)
              tried Meditations/\(base).mp3: nil
              tried flat \(base).mp3:        nil
            """)
            #endif
            return
        }

        #if DEBUG
        print("FileAudioEngine: resolved '\(resource)' -> \(url.path)")
        #endif

        // Audio session is owned by MeditationAudioController (.playback), so
        // bundled playback shares the same route as streaming and shows on the
        // lock screen.

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1  // seamless loop, regardless of session length
            player.volume = 0
            player.prepareToPlay()
            player.play()
            self.player = player
            fade(to: targetVolume, duration: 2.0)
        } catch {
            #if DEBUG
            print("FileAudioEngine: failed to start \(resource) at \(url.path): \(error)")
            #endif
        }
    }

    func pause() {
        guard let player, player.isPlaying else { return }
        fade(to: 0, duration: 0.5) { [weak self] in
            self?.player?.pause()
        }
    }

    func resume() {
        guard let player, !player.isPlaying else { return }
        player.play()
        fade(to: targetVolume, duration: 1.0)
    }

    func stop(fade duration: Double = 1.0) {
        guard player != nil else { return }
        fade(to: 0, duration: duration) { [weak self] in
            self?.player?.stop()
            self?.player = nil
        }
    }

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
}
