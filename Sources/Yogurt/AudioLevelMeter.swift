import AVFoundation
import Accelerate
import Combine
import os

/// One channel's display levels, in dBFS (0 = full scale, floor = -60).
struct ChannelLevel: Equatable {
    /// Average loudness.
    var rms: Float
    /// Live peak, with a short release so it reads as a shade rather than flicker.
    var peak: Float
    /// Highest recent peak: held briefly, then falls.
    var hold: Float
    static let silent = ChannelLevel(
        rms: AudioLevelMeter.floorDB, peak: AudioLevelMeter.floorDB, hold: AudioLevelMeter.floorDB
    )
}

/// Reads live audio levels off the player's audio without disturbing playback.
///
/// An `MTAudioProcessingTap` installed on the item's `audioMix` hands us raw PCM
/// on a real-time thread; the tap callback computes per-channel RMS/peak into a
/// lock-guarded `TapStorage`, and a main-thread timer samples that into the
/// published `levels` (applying peak-hold decay) for SwiftUI to render.
@MainActor
final class AudioLevelMeter: ObservableObject {
    static let floorDB: Float = -60

    /// Index 0 = left, 1 = right. Mono sources duplicate to both.
    @Published private(set) var levels: [ChannelLevel] = [.silent, .silent]

    private var storage: TapStorage?
    private var audioMix: AVMutableAudioMix?
    private weak var currentItem: AVPlayerItem?
    private var displayTimer: Timer?
    private var peakDB: [Float] = [floorDB, floorDB]
    private var holdDB: [Float] = [floorDB, floorDB]
    private var holdTicksLeft: [Int] = [0, 0]

    private let refreshInterval = 1.0 / 60.0
    private let peakReleasePerSecond: Float = 24 // dB/sec fall-off of the live-peak shade
    private let holdSeconds = 1.5                 // how long the peak-hold line stays put
    private let holdFallPerSecond: Float = 12     // dB/sec fall-off of the line once released

    // MARK: Tap lifecycle

    /// Install a fresh tap on `item`. Safe to call again on file switch.
    func attach(to item: AVPlayerItem, asset: AVAsset) {
        detach()
        currentItem = item
        Task { @MainActor [weak self] in
            let tracks = try? await asset.loadTracks(withMediaType: .audio)
            guard let self, let track = tracks?.first, self.currentItem === item else { return }
            self.installTap(on: item, track: track)
        }
    }

    /// Tear down the tap (keeps the display timer; a reattach is expected on file switch).
    func detach() {
        currentItem?.audioMix = nil
        currentItem = nil
        audioMix = nil
        storage = nil
    }

    private func installTap(on item: AVPlayerItem, track: AVAssetTrack) {
        let storage = TapStorage()
        self.storage = storage

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(storage).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: nil,
            unprepare: nil,
            process: tapProcess
        )

        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let tap else {
            // Balance the passRetained above if creation failed (init never ran).
            Unmanaged<TapStorage>.fromOpaque(callbacks.clientInfo!).release()
            self.storage = nil
            return
        }

        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap.takeRetainedValue()
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
        audioMix = mix
    }

    // MARK: Display timer

    /// Begin sampling levels for display (~60 Hz). Idempotent.
    func startMetering() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Timer fires on the main run loop; hop to the actor for the isolated call.
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Stop sampling and reset the display to silence.
    func stopMetering() {
        displayTimer?.invalidate()
        displayTimer = nil
        peakDB = [Self.floorDB, Self.floorDB]
        holdDB = [Self.floorDB, Self.floorDB]
        holdTicksLeft = [0, 0]
        levels = [.silent, .silent]
    }

    private func tick() {
        guard let storage else { return }
        let snap = storage.read()
        let peakRelease = peakReleasePerSecond * Float(refreshInterval)
        let holdFall = holdFallPerSecond * Float(refreshInterval)
        let holdTicks = Int(holdSeconds / refreshInterval)

        var next: [ChannelLevel] = []
        for ch in 0..<2 {
            let src = snap.count <= 1 ? 0 : ch
            let rmsDB = Self.toDB(snap.rms[src])
            let nowDB = Self.toDB(snap.peak[src])

            // Live peak: instant attack, steady release.
            peakDB[ch] = max(nowDB, peakDB[ch] - peakRelease)

            // Peak-hold line: latch new highs, wait, then fall (never below the live peak).
            if peakDB[ch] >= holdDB[ch] {
                holdDB[ch] = peakDB[ch]
                holdTicksLeft[ch] = holdTicks
            } else if holdTicksLeft[ch] > 0 {
                holdTicksLeft[ch] -= 1
            } else {
                holdDB[ch] = max(peakDB[ch], holdDB[ch] - holdFall)
            }

            next.append(ChannelLevel(rms: rmsDB, peak: peakDB[ch], hold: holdDB[ch]))
        }
        levels = next
    }

    static func toDB(_ linear: Float) -> Float {
        guard linear > 0 else { return floorDB }
        return max(floorDB, min(0, 20 * log10(linear)))
    }
}

// MARK: - Real-time storage

/// Scratchpad shared between the real-time tap callback (writer) and the
/// main-thread display timer (reader). Values are linear magnitudes (0...1).
private final class TapStorage {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private var rms: [Float] = [0, 0]
    private var peak: [Float] = [0, 0]
    private var count = 2

    init() { lock.initialize(to: os_unfair_lock()) }
    deinit { lock.deinitialize(count: 1); lock.deallocate() }

    func write(rms0: Float, peak0: Float, rms1: Float, peak1: Float, count: Int) {
        os_unfair_lock_lock(lock)
        rms[0] = rms0; peak[0] = peak0
        rms[1] = rms1; peak[1] = peak1
        self.count = count
        os_unfair_lock_unlock(lock)
    }

    func read() -> (rms: [Float], peak: [Float], count: Int) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return (rms, peak, count)
    }
}

// MARK: - Tap callbacks (C function pointers — must not capture state)

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<TapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut
    )
    guard status == noErr else { return }

    let storage = Unmanaged<TapStorage>
        .fromOpaque(MTAudioProcessingTapGetStorage(tap))
        .takeUnretainedValue()

    let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    guard abl.count > 0 else { return }

    var r0: Float = 0, p0: Float = 0, r1: Float = 0, p1: Float = 0
    var channels = 0

    if abl.count > 1 {
        // Non-interleaved: one buffer per channel.
        channels = abl.count
        if let d = abl[0].mData {
            let n = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            if n > 0 { (r0, p0) = measure(d.assumingMemoryBound(to: Float.self), stride: 1, count: n) }
        }
        if abl.count > 1, let d = abl[1].mData {
            let n = Int(abl[1].mDataByteSize) / MemoryLayout<Float>.size
            if n > 0 { (r1, p1) = measure(d.assumingMemoryBound(to: Float.self), stride: 1, count: n) }
        }
    } else {
        // Interleaved: one buffer, samples strided by channel count.
        let buf = abl[0]
        channels = Int(buf.mNumberChannels)
        guard let d = buf.mData, channels > 0 else { return }
        let total = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let frames = total / channels
        guard frames > 0 else { return }
        let p = d.assumingMemoryBound(to: Float.self)
        (r0, p0) = measure(p, stride: channels, count: frames)
        if channels > 1 { (r1, p1) = measure(p + 1, stride: channels, count: frames) }
    }

    storage.write(rms0: r0, peak0: p0, rms1: r1, peak1: p1, count: min(channels, 2))
}

/// RMS and peak magnitude over a (possibly strided) run of Float samples.
private func measure(_ base: UnsafePointer<Float>, stride: Int, count: Int) -> (rms: Float, peak: Float) {
    var rms: Float = 0
    var peak: Float = 0
    vDSP_rmsqv(base, vDSP_Stride(stride), &rms, vDSP_Length(count))
    vDSP_maxmgv(base, vDSP_Stride(stride), &peak, vDSP_Length(count))
    return (rms, peak)
}
