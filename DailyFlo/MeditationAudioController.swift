//
//  MeditationAudioController.swift
//  DailyFlo
//
//  Unified audio surface for the meditation player. Picks between a
//  bundled MP3 (looped via AVAudioPlayer) and the synthesized
//  AmbientAudioEngine fallback based on the session passed in. Exposes
//  the play/pause/resume/stop interface the player view already uses.
//

import AVFoundation
import Observation

@MainActor
@Observable
final class MeditationAudioController {
    private var fileEngine: FileAudioEngine?
    private var synthEngine: AmbientAudioEngine?

    private(set) var isPlaying = false

    /// Begins playback for the given session. If the session ships with a
    /// bundled MP3, that file is looped; otherwise we fall back to the
    /// synthesized ambient sound. Either way the call is fire-and-forget.
    func play(session: MeditationSession) {
        stop()
        if let filename = session.audioFileName {
            let engine = FileAudioEngine()
            engine.play(resource: filename)
            fileEngine = engine
        } else {
            let engine = AmbientAudioEngine()
            engine.play(sound: session.ambientSound)
            synthEngine = engine
        }
        isPlaying = true
    }

    func pause() {
        fileEngine?.pause()
        synthEngine?.pause()
        isPlaying = false
    }

    func resume() {
        fileEngine?.resume()
        synthEngine?.resume()
        isPlaying = true
    }

    /// Stops playback with an optional custom fade. Default is the snappy
    /// 1-second fade used when the user explicitly stops (X / dismiss).
    /// A longer fade (3–5s) is appropriate at natural session-end so the
    /// loop bleeds out gently instead of cutting off.
    func stop(fade: Double = 1.0) {
        fileEngine?.stop(fade: fade)
        synthEngine?.stop()
        fileEngine = nil
        synthEngine = nil
        isPlaying = false
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

        let url = Bundle.main.url(forResource: base, withExtension: "mp3", subdirectory: "Meditations")
            ?? Bundle.main.url(forResource: base, withExtension: "mp3")

        guard let url else {
            print("FileAudioEngine: missing audio resource \(resource)")
            return
        }

        configureAudioSession()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1  // seamless loop, regardless of session length
            player.volume = 0
            player.prepareToPlay()
            player.play()
            self.player = player
            fade(to: targetVolume, duration: 2.0)
        } catch {
            print("FileAudioEngine: failed to start \(resource): \(error)")
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

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("FileAudioEngine: audio session error: \(error)")
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
