import AVFoundation
import Foundation

/// Everything the info panel shows about the open file. Every field is optional:
/// whatever can't be read stays nil and renders blank.
struct MediaInfo {
    var container: String?
    var fileSize: Int64?
    var created: Date?
    var modified: Date?
    var duration: Double?

    var audioCodec: String?
    var channels: Int?
    var bitDepth: Int?
    var sampleRate: Double?
    var bitRate: Float?

    var hasVideo = false
    var videoCodec: String?
    var dimensions: CGSize?
    var frameRate: Float?

    var title: String?
    var artist: String?
    var album: String?

    var ableton: AbletonAnalysis?
    var levels: AudioLevels?

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// Display rows; related values share a line. Rows whose data is missing keep
    /// an empty value. The Video row only appears for files with a video track.
    var rows: [Row] {
        var rows = [
            Row(label: "File", value: Self.join(container, fileSize.map(Self.formatSize))),
            Row(label: "Audio", value: Self.join(audioCodec, channels.map(Self.formatChannels))),
            Row(label: "Quality", value: Self.join(
                bitDepth.map { "\($0)-bit" },
                sampleRate.map(Self.formatSampleRate),
                bitRate.map(Self.formatBitRate)
            )),
            Row(label: "Duration", value: duration.map(PlayerController.format) ?? ""),
        ]
        if hasVideo {
            rows.append(Row(label: "Video", value: Self.join(
                videoCodec,
                dimensions.map { "\(Int($0.width))×\(Int($0.height))" },
                frameRate.map { String(format: "%g fps", ($0 * 100).rounded() / 100) }
            )))
        }
        rows += [
            Row(label: "Tempo", value: Self.join(
                ableton?.bpm.map { String(format: "%g BPM", ($0 * 100).rounded() / 100) },
                ableton?.timeSignature.map { "\($0.numerator)/\($0.denominator)" }
            )),
            Row(label: "Track", value: Self.join(
                [artist, title].compactMap { $0 }.joined(separator: " – ").nilIfEmpty,
                album
            )),
            Row(label: "Dates", value: Self.join(
                created.map { "Created \(Self.formatDate($0))" },
                modified.map { "Modified \(Self.formatDate($0))" }
            )),
            Row(label: "Levels", value: Self.join(
                levels?.integratedLUFS.map { String(format: "%.1f LUFS", $0) },
                levels.map { "RMS \(Self.formatDB($0.rmsDB))" },
                levels.map { "Peak \(Self.formatDB($0.peakDB))" + ($0.clips ? " (clips)" : "") }
            )),
            Row(label: "Silence", value: Self.join(
                levels.map { String(format: "%.2f s start", $0.leadingSilence) },
                levels.map { String(format: "%.2f s end", $0.trailingSilence) }
            )),
            Row(label: "Stereo", value: levels?.correlation.map {
                String(format: "Correlation %+.2f", $0)
            } ?? ""),
        ]
        return rows
    }

    /// Markdown list for the notes; rows with no data are left out.
    var markdown: String {
        let lines = rows.filter { !$0.value.isEmpty }.map { "- \($0.label): \($0.value)" }
        return "\n## File info\n\n" + lines.joined(separator: "\n") + "\n"
    }

    private static func join(_ parts: String?...) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }

    private static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func formatChannels(_ count: Int) -> String {
        switch count {
        case 1: return "Mono"
        case 2: return "Stereo"
        default: return "\(count) ch"
        }
    }

    private static func formatSampleRate(_ hz: Double) -> String {
        String(format: "%g kHz", hz / 1000)
    }

    private static func formatBitRate(_ bitsPerSecond: Float) -> String {
        "\(Int((bitsPerSecond / 1000).rounded()).formatted()) kbps"
    }

    private static func formatDB(_ db: Float) -> String {
        db.isFinite ? String(format: "%.1f dBFS", db) : "-∞ dBFS"
    }

    private static func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Loading

extension MediaInfo {
    /// File attributes, container/track properties, tags and the Ableton sidecar.
    /// Fast: reads headers only. Levels come separately from `AudioLevels.measure`.
    static func load(url: URL) async -> MediaInfo {
        var info = MediaInfo()
        info.container = url.pathExtension.isEmpty ? nil : url.pathExtension.uppercased()

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            info.fileSize = (attributes[.size] as? NSNumber)?.int64Value
            info.created = attributes[.creationDate] as? Date
            info.modified = attributes[.modificationDate] as? Date
        }
        info.ableton = AbletonAnalysis.load(for: url)

        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            info.duration = duration.seconds
        }

        if let track = try? await asset.loadTracks(withMediaType: .audio).first {
            if let format = try? await track.load(.formatDescriptions).first {
                info.audioCodec = codecName(format.mediaSubType.rawValue)
                if let asbd = format.audioStreamBasicDescription {
                    info.channels = Int(asbd.mChannelsPerFrame)
                    info.sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : nil
                    info.bitDepth = asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : nil
                }
            }
            if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                info.bitRate = rate
            } else if info.audioCodec == "Linear PCM",
                      let rate = info.sampleRate, let channels = info.channels, let depth = info.bitDepth {
                // AVFoundation reports no data rate for uncompressed audio.
                info.bitRate = Float(rate) * Float(channels * depth)
            }
        }

        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            info.hasVideo = true
            if let format = try? await track.load(.formatDescriptions).first {
                info.videoCodec = codecName(format.mediaSubType.rawValue)
            }
            if let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let rotated = size.applying(transform)
                info.dimensions = CGSize(width: abs(rotated.width), height: abs(rotated.height))
            }
            if let fps = try? await track.load(.nominalFrameRate), fps > 0 {
                info.frameRate = fps
            }
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            func string(_ key: AVMetadataKey) async -> String? {
                let item = AVMetadataItem.metadataItems(
                    from: metadata, withKey: key, keySpace: .common
                ).first
                let value = try? await item?.load(.stringValue)
                return value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            info.title = await string(.commonKeyTitle)
            info.artist = await string(.commonKeyArtist)
            info.album = await string(.commonKeyAlbumName)
        }
        return info
    }

    private static func codecName(_ fourCC: FourCharCode) -> String {
        let names: [String: String] = [
            "lpcm": "Linear PCM", ".mp3": "MP3", "aac ": "AAC", "alac": "Apple Lossless",
            "flac": "FLAC", "opus": "Opus", "ac-3": "AC-3", "ec-3": "E-AC-3",
            "avc1": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "av01": "AV1", "vp09": "VP9",
            "ap4h": "ProRes 4444", "ap4x": "ProRes 4444 XQ", "apch": "ProRes 422 HQ",
            "apcn": "ProRes 422", "apcs": "ProRes 422 LT", "apco": "ProRes 422 Proxy",
            "jpeg": "Motion JPEG",
        ]
        let code = String(bytes: [24, 16, 8, 0].map { UInt8((fourCC >> $0) & 0xFF) }, encoding: .macOSRoman) ?? ""
        return names[code] ?? code.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Level analysis

/// Measurements taken by decoding the whole audio track once.
struct AudioLevels {
    var peakDB: Float
    var rmsDB: Float
    /// ITU-R BS.1770 integrated loudness (K-weighted, gated). Nil if the file is
    /// too short or too quiet to pass the gates.
    var integratedLUFS: Double?
    var clips: Bool
    var leadingSilence: Double
    var trailingSilence: Double
    /// L/R correlation (+1 mono-like, 0 wide, negative = phase problems); stereo only.
    var correlation: Float?

    /// Samples quieter than this count as silence.
    private static let silenceThreshold: Float = 0.001  // -60 dBFS

    static func measure(url: URL) async -> AudioLevels? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let format = try? await track.load(.formatDescriptions).first,
              let asbd = format.audioStreamBasicDescription,
              asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0,
              let reader = try? AVAssetReader(asset: asset)
        else { return nil }

        let channels = Int(asbd.mChannelsPerFrame)
        let sampleRate = asbd.mSampleRate
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var accumulator = Accumulator(channels: channels, sampleRate: sampleRate)
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil,
                totalLengthOut: &length, dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer,
                CMBlockBufferIsRangeContiguous(block, atOffset: 0, length: length)
            else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) {
                accumulator.add(UnsafeBufferPointer(start: $0, count: length / 4))
            }
        }
        guard reader.status == .completed else { return nil }
        return accumulator.result()
    }

    /// Single-pass running totals.
    private struct Accumulator {
        let channels: Int
        let sampleRate: Double
        var frames = 0
        var peak: Float = 0
        var sumSquares: Double = 0
        var firstAudible: Int?
        var lastAudible: Int?
        var sumLR: Double = 0, sumLL: Double = 0, sumRR: Double = 0

        // Loudness: K-weighting filters per channel, mean-square per 100 ms segment.
        var shelf: [Biquad]
        var highPass: [Biquad]
        let segmentLength: Int
        var segmentFill = 0
        var segmentPower: Double = 0
        var segments: [Double] = []

        init(channels: Int, sampleRate: Double) {
            self.channels = channels
            self.sampleRate = sampleRate
            shelf = Array(repeating: .kWeightingShelf(sampleRate: sampleRate), count: channels)
            highPass = Array(repeating: .kWeightingHighPass(sampleRate: sampleRate), count: channels)
            segmentLength = max(1, Int(sampleRate / 10))
        }

        mutating func add(_ samples: UnsafeBufferPointer<Float>) {
            let frameCount = samples.count / channels
            for f in 0..<frameCount {
                var frameMax: Float = 0
                var weighted: Double = 0
                for c in 0..<channels {
                    let x = samples[f * channels + c]
                    let a = abs(x)
                    frameMax = max(frameMax, a)
                    sumSquares += Double(x * x)
                    let k = highPass[c].process(shelf[c].process(Double(x)))
                    weighted += k * k  // channel weight 1.0 (L, R, C)
                }
                peak = max(peak, frameMax)
                if frameMax > AudioLevels.silenceThreshold {
                    if firstAudible == nil { firstAudible = frames }
                    lastAudible = frames
                }
                if channels == 2 {
                    let l = Double(samples[f * 2]), r = Double(samples[f * 2 + 1])
                    sumLR += l * r; sumLL += l * l; sumRR += r * r
                }
                segmentPower += weighted
                segmentFill += 1
                if segmentFill == segmentLength {
                    segments.append(segmentPower / Double(segmentLength))
                    segmentPower = 0
                    segmentFill = 0
                }
                frames += 1
            }
        }

        func result() -> AudioLevels? {
            guard frames > 0 else { return nil }
            let rms = sqrt(sumSquares / Double(frames * channels))
            let duration = Double(frames) / sampleRate
            let correlation: Float? = channels == 2 && sumLL > 0 && sumRR > 0
                ? Float(sumLR / sqrt(sumLL * sumRR)) : nil
            return AudioLevels(
                peakDB: 20 * log10(peak),
                rmsDB: Float(20 * log10(rms)),
                integratedLUFS: integratedLoudness(),
                clips: peak >= 0.9999,
                leadingSilence: firstAudible.map { Double($0) / sampleRate } ?? duration,
                trailingSilence: lastAudible.map { Double(frames - 1 - $0) / sampleRate } ?? duration,
                correlation: correlation
            )
        }

        /// 400 ms blocks with 75% overlap (four 100 ms segments), absolute gate at
        /// -70 LUFS, relative gate 10 LU below the absolute-gated mean.
        private func integratedLoudness() -> Double? {
            guard segments.count >= 4 else { return nil }
            let blocks = (0...(segments.count - 4)).map { i in
                segments[i..<(i + 4)].reduce(0, +) / 4
            }
            func lufs(_ power: Double) -> Double { -0.691 + 10 * log10(power) }
            let absoluteGated = blocks.filter { lufs($0) > -70 }
            guard !absoluteGated.isEmpty else { return nil }
            let relativeGate = lufs(absoluteGated.reduce(0, +) / Double(absoluteGated.count)) - 10
            let gated = absoluteGated.filter { lufs($0) > relativeGate }
            guard !gated.isEmpty else { return nil }
            return lufs(gated.reduce(0, +) / Double(gated.count))
        }
    }
}

/// Direct-form I biquad; coefficients normalised so a0 = 1.
private struct Biquad {
    let b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0
        self.a1 = a1 / a0; self.a2 = a2 / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }

    /// BS.1770 stage 1: +4 dB high shelf, derived for any sample rate
    /// (same parameterisation as libebur128).
    static func kWeightingShelf(sampleRate: Double) -> Biquad {
        let fc = 1681.974450955533, gain = 3.999843853973347, q = 0.7071752369554196
        let k = tan(Double.pi * fc / sampleRate)
        let vh = pow(10, gain / 20)
        let vb = pow(vh, 0.4996667741545416)
        return Biquad(
            b0: vh + vb * k / q + k * k,
            b1: 2 * (k * k - vh),
            b2: vh - vb * k / q + k * k,
            a0: 1 + k / q + k * k,
            a1: 2 * (k * k - 1),
            a2: 1 - k / q + k * k
        )
    }

    /// BS.1770 stage 2: high-pass around 38 Hz.
    static func kWeightingHighPass(sampleRate: Double) -> Biquad {
        let fc = 38.13547087602444, q = 0.5003270373238773
        let k = tan(Double.pi * fc / sampleRate)
        let a0 = 1 + k / q + k * k
        // The spec leaves the numerator at 1, -2, 1 (not divided by a0).
        return Biquad(
            b0: a0, b1: -2 * a0, b2: a0,
            a0: a0,
            a1: 2 * (k * k - 1),
            a2: 1 - k / q + k * k
        )
    }
}
