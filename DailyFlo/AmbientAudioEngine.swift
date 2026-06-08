//
//  AmbientAudioEngine.swift
//  DailyFlo
//
//  Generates calming ambient soundscapes programmatically using AVAudioEngine.
//  No audio files required — all sounds are synthesized in real-time.
//

import AVFoundation

// MARK: - Ambient Sound Type
enum AmbientSoundType: String, CaseIterable {
    case oceanWaves
    case gentleRain
    case forestBreeze
    case nightAmbience
    case warmDrone
    case softChimes

    var displayName: String {
        switch self {
        case .oceanWaves: return "Ocean Waves"
        case .gentleRain: return "Gentle Rain"
        case .forestBreeze: return "Forest Breeze"
        case .nightAmbience: return "Night Ambience"
        case .warmDrone: return "Warm Drone"
        case .softChimes: return "Soft Chimes"
        }
    }
}

// MARK: - Ambient Audio Engine
/// Synthesizes calming ambient audio using AVAudioEngine with layered oscillators and noise.
@Observable
class AmbientAudioEngine {
    private var audioEngine: AVAudioEngine?
    private var noiseNode: AVAudioPlayerNode?
    private var noiseBuffer: AVAudioPCMBuffer?
    private var toneNodes: [AVAudioPlayerNode] = []
    private var toneBuffers: [AVAudioPCMBuffer] = []
    private var mixerNode: AVAudioMixerNode?

    private(set) var isPlaying = false
    private(set) var currentSound: AmbientSoundType?

    private let sampleRate: Double = 44100.0
    private let bufferDuration: Double = 2.0 // seconds per buffer loop

    // MARK: - Public API

    /// Throws on failed AVAudioEngine startup or audio-session setup so the
    /// caller (MeditationAudioController) can surface a precise miss-report
    /// to the console instead of swallowing the error.
    func play(sound: AmbientSoundType) throws {
        stop()
        try configureAudioSession()
        currentSound = sound

        let engine = AVAudioEngine()
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        switch sound {
        case .oceanWaves:
            setupOceanWaves(engine: engine, mixer: mixer, format: format)
        case .gentleRain:
            setupGentleRain(engine: engine, mixer: mixer, format: format)
        case .forestBreeze:
            setupForestBreeze(engine: engine, mixer: mixer, format: format)
        case .nightAmbience:
            setupNightAmbience(engine: engine, mixer: mixer, format: format)
        case .warmDrone:
            setupWarmDrone(engine: engine, mixer: mixer, format: format)
        case .softChimes:
            setupSoftChimes(engine: engine, mixer: mixer, format: format)
        }

        // Connect mixer to main output
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0

        try engine.start()

        // Engine is running — NOW it's safe to start each player node.
        // Calling node.play() before engine.start() silently fails with
        // "Engine is not running ... Cannot play yet!" in the console
        // and produces no audio.
        noiseNode?.play()
        toneNodes.forEach { $0.play() }

        self.audioEngine = engine
        self.mixerNode = mixer
        self.isPlaying = true

        // Fade in over 2 seconds
        fadeVolume(to: 0.7, duration: 2.0)
    }

    func pause() {
        guard isPlaying else { return }
        fadeVolume(to: 0.0, duration: 0.5) {
            self.audioEngine?.pause()
            self.isPlaying = false
        }
    }

    func resume() {
        guard !isPlaying, audioEngine != nil else { return }
        do {
            try audioEngine?.start()
            isPlaying = true
            fadeVolume(to: 0.7, duration: 1.0)
        } catch {
            print("AmbientAudioEngine: Failed to resume: \(error)")
        }
    }

    func stop() {
        fadeVolume(to: 0.0, duration: 1.0) {
            self.toneNodes.forEach { $0.stop() }
            self.noiseNode?.stop()
            self.audioEngine?.stop()

            self.toneNodes.removeAll()
            self.toneBuffers.removeAll()
            self.noiseNode = nil
            self.noiseBuffer = nil
            self.audioEngine = nil
            self.mixerNode = nil
            self.isPlaying = false
            self.currentSound = nil
        }
    }

    // MARK: - Audio Session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    // MARK: - Volume Fade

    private func fadeVolume(to target: Float, duration: Double, completion: (() -> Void)? = nil) {
        guard let engine = audioEngine else {
            completion?()
            return
        }

        let steps = 30
        let interval = duration / Double(steps)
        let currentVolume = engine.mainMixerNode.outputVolume
        let delta = (target - currentVolume) / Float(steps)

        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                if i == steps {
                    engine.mainMixerNode.outputVolume = target
                    completion?()
                } else {
                    engine.mainMixerNode.outputVolume = currentVolume + delta * Float(i)
                }
            }
        }
    }

    // MARK: - Sound Generators

    /// Ocean waves: filtered noise with slow amplitude modulation
    private func setupOceanWaves(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Low rumble (filtered noise)
        let lowNoise = createNoiseBuffer(format: format, volume: 0.3, lowPass: 200, highPass: 40)
        let lowNode = scheduleLoopingBuffer(lowNoise, on: engine, mixer: mixer, format: format, volume: 0.5)

        // Layer 2: Mid wash (filtered noise)
        let midNoise = createNoiseBuffer(format: format, volume: 0.2, lowPass: 800, highPass: 100)
        let midNode = scheduleLoopingBuffer(midNoise, on: engine, mixer: mixer, format: format, volume: 0.35)

        // Layer 3: Soft high hiss (surf foam)
        let highNoise = createNoiseBuffer(format: format, volume: 0.08, lowPass: 6000, highPass: 2000)
        let highNode = scheduleLoopingBuffer(highNoise, on: engine, mixer: mixer, format: format, volume: 0.2)

        toneNodes.append(contentsOf: [lowNode, midNode, highNode])
    }

    /// Gentle rain: broadband noise with gentle filtering
    private func setupGentleRain(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Broad rain noise
        let rainNoise = createNoiseBuffer(format: format, volume: 0.15, lowPass: 8000, highPass: 200)
        let rainNode = scheduleLoopingBuffer(rainNoise, on: engine, mixer: mixer, format: format, volume: 0.4)

        // Layer 2: Soft low rumble (distant thunder ambience)
        let rumbleNoise = createNoiseBuffer(format: format, volume: 0.1, lowPass: 150, highPass: 30)
        let rumbleNode = scheduleLoopingBuffer(rumbleNoise, on: engine, mixer: mixer, format: format, volume: 0.25)

        // Layer 3: High patter detail
        let patterNoise = createNoiseBuffer(format: format, volume: 0.05, lowPass: 12000, highPass: 4000)
        let patterNode = scheduleLoopingBuffer(patterNoise, on: engine, mixer: mixer, format: format, volume: 0.15)

        toneNodes.append(contentsOf: [rainNode, rumbleNode, patterNode])
    }

    /// Forest breeze: noise with subtle tonal undertones
    private func setupForestBreeze(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Wind noise
        let windNoise = createNoiseBuffer(format: format, volume: 0.12, lowPass: 3000, highPass: 100)
        let windNode = scheduleLoopingBuffer(windNoise, on: engine, mixer: mixer, format: format, volume: 0.4)

        // Layer 2: Very soft tone (rustling leaves feel)
        let leafTone = createToneBuffer(format: format, frequency: 420, volume: 0.02, harmonics: [0.5, 0.3])
        let leafNode = scheduleLoopingBuffer(leafTone, on: engine, mixer: mixer, format: format, volume: 0.15)

        // Layer 3: Sub bass warmth
        let bassNoise = createNoiseBuffer(format: format, volume: 0.08, lowPass: 120, highPass: 30)
        let bassNode = scheduleLoopingBuffer(bassNoise, on: engine, mixer: mixer, format: format, volume: 0.2)

        toneNodes.append(contentsOf: [windNode, leafNode, bassNode])
    }

    /// Night ambience: deep droning with cricket-like high tones
    private func setupNightAmbience(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Deep night drone
        let drone = createToneBuffer(format: format, frequency: 85, volume: 0.08, harmonics: [0.6, 0.3, 0.15])
        let droneNode = scheduleLoopingBuffer(drone, on: engine, mixer: mixer, format: format, volume: 0.35)

        // Layer 2: Soft noise bed
        let noiseBed = createNoiseBuffer(format: format, volume: 0.06, lowPass: 2000, highPass: 60)
        let noiseNode = scheduleLoopingBuffer(noiseBed, on: engine, mixer: mixer, format: format, volume: 0.25)

        // Layer 3: High shimmer (cricket-like)
        let shimmer = createToneBuffer(format: format, frequency: 3800, volume: 0.015, harmonics: [0.4])
        let shimmerNode = scheduleLoopingBuffer(shimmer, on: engine, mixer: mixer, format: format, volume: 0.12)

        toneNodes.append(contentsOf: [droneNode, noiseNode, shimmerNode])
    }

    /// Warm drone: rich harmonic tones layered for a meditative hum
    private func setupWarmDrone(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Root tone
        let root = createToneBuffer(format: format, frequency: 110, volume: 0.1, harmonics: [0.5, 0.25, 0.12])
        let rootNode = scheduleLoopingBuffer(root, on: engine, mixer: mixer, format: format, volume: 0.35)

        // Layer 2: Fifth above
        let fifth = createToneBuffer(format: format, frequency: 165, volume: 0.06, harmonics: [0.4, 0.2])
        let fifthNode = scheduleLoopingBuffer(fifth, on: engine, mixer: mixer, format: format, volume: 0.25)

        // Layer 3: Octave above
        let octave = createToneBuffer(format: format, frequency: 220, volume: 0.04, harmonics: [0.3, 0.15])
        let octaveNode = scheduleLoopingBuffer(octave, on: engine, mixer: mixer, format: format, volume: 0.2)

        // Layer 4: Subtle noise for texture
        let texture = createNoiseBuffer(format: format, volume: 0.02, lowPass: 500, highPass: 80)
        let textureNode = scheduleLoopingBuffer(texture, on: engine, mixer: mixer, format: format, volume: 0.1)

        toneNodes.append(contentsOf: [rootNode, fifthNode, octaveNode, textureNode])
    }

    /// Soft chimes: gentle tones with noise bed
    private func setupSoftChimes(engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat) {
        // Layer 1: Soft noise bed
        let bed = createNoiseBuffer(format: format, volume: 0.08, lowPass: 3000, highPass: 80)
        let bedNode = scheduleLoopingBuffer(bed, on: engine, mixer: mixer, format: format, volume: 0.3)

        // Layer 2: Chime tone (C5)
        let chime1 = createToneBuffer(format: format, frequency: 523.25, volume: 0.04, harmonics: [0.3, 0.1])
        let chime1Node = scheduleLoopingBuffer(chime1, on: engine, mixer: mixer, format: format, volume: 0.2)

        // Layer 3: Chime tone (E5)
        let chime2 = createToneBuffer(format: format, frequency: 659.25, volume: 0.03, harmonics: [0.25, 0.08])
        let chime2Node = scheduleLoopingBuffer(chime2, on: engine, mixer: mixer, format: format, volume: 0.15)

        // Layer 4: Chime tone (G5)
        let chime3 = createToneBuffer(format: format, frequency: 783.99, volume: 0.02, harmonics: [0.2, 0.06])
        let chime3Node = scheduleLoopingBuffer(chime3, on: engine, mixer: mixer, format: format, volume: 0.12)

        toneNodes.append(contentsOf: [bedNode, chime1Node, chime2Node, chime3Node])
    }

    // MARK: - Buffer Creation

    /// Creates a PCM buffer filled with band-limited noise
    private func createNoiseBuffer(format: AVAudioFormat, volume: Float, lowPass: Float, highPass: Float) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return buffer }

        // Generate white noise then apply simple band-pass via averaging (low-pass approximation)
        var rawNoise = [Float](repeating: 0, count: Int(frameCount))
        for i in 0..<Int(frameCount) {
            rawNoise[i] = Float.random(in: -1...1) * volume
        }

        // Simple low-pass filter using moving average
        let lpCoeff = exp(-2.0 * Float.pi * lowPass / Float(sampleRate))
        let hpCoeff = exp(-2.0 * Float.pi * highPass / Float(sampleRate))

        var lpFiltered = [Float](repeating: 0, count: Int(frameCount))
        var hpFiltered = [Float](repeating: 0, count: Int(frameCount))

        // Low-pass
        lpFiltered[0] = rawNoise[0]
        for i in 1..<Int(frameCount) {
            lpFiltered[i] = lpCoeff * lpFiltered[i - 1] + (1 - lpCoeff) * rawNoise[i]
        }

        // High-pass (subtract low-passed version at highPass frequency)
        hpFiltered[0] = lpFiltered[0]
        var hpState: Float = 0
        for i in 1..<Int(frameCount) {
            hpState = hpCoeff * hpState + (1 - hpCoeff) * lpFiltered[i]
            hpFiltered[i] = lpFiltered[i] - hpState
        }

        // Apply gentle amplitude envelope for smooth looping
        let fadeFrames = Int(sampleRate * 0.15) // 150ms fade
        for i in 0..<Int(frameCount) {
            var env: Float = 1.0
            if i < fadeFrames {
                env = Float(i) / Float(fadeFrames)
            } else if i > Int(frameCount) - fadeFrames {
                env = Float(Int(frameCount) - i) / Float(fadeFrames)
            }

            let sample = hpFiltered[i] * env
            // Slight stereo variation
            leftChannel[i] = sample
            rightChannel[i] = sample * 0.92 + Float.random(in: -0.002...0.002)
        }

        return buffer
    }

    /// Creates a PCM buffer with a sine tone and optional harmonics
    private func createToneBuffer(format: AVAudioFormat, frequency: Double, volume: Float, harmonics: [Float] = []) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * bufferDuration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else { return buffer }

        let twoPi = 2.0 * Double.pi
        let fadeFrames = Int(sampleRate * 0.15)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate

            // Fundamental
            var sample = Float(sin(twoPi * frequency * t)) * volume

            // Add harmonics
            for (idx, harmVolume) in harmonics.enumerated() {
                let harmFreq = frequency * Double(idx + 2)
                sample += Float(sin(twoPi * harmFreq * t)) * volume * harmVolume
            }

            // Smooth loop envelope
            var env: Float = 1.0
            if i < fadeFrames {
                env = Float(i) / Float(fadeFrames)
            } else if i > Int(frameCount) - fadeFrames {
                env = Float(Int(frameCount) - i) / Float(fadeFrames)
            }

            sample *= env
            leftChannel[i] = sample
            rightChannel[i] = sample * 0.95 // Slight stereo width
        }

        return buffer
    }

    /// Attaches a player node, connects it to the mixer, and schedules a
    /// looping buffer. Does NOT call `player.play()` — per AVFoundation,
    /// calling play() before `engine.start()` triggers the runtime warning
    /// "AVAudioPlayerNode ... Engine is not running ... Cannot play yet!"
    /// and the node never actually produces sound. The caller starts all
    /// nodes after `engine.start()` returns.
    @discardableResult
    private func scheduleLoopingBuffer(_ buffer: AVAudioPCMBuffer, on engine: AVAudioEngine, mixer: AVAudioMixerNode, format: AVAudioFormat, volume: Float) -> AVAudioPlayerNode {
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: format)
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        return player
    }
}
