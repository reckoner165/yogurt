import Foundation

/// Tempo and time signature from Ableton Live's analysis sidecar
/// (`<media filename>.asd`, next to the media file).
///
/// The format is undocumented; this reads it by locating known field names and
/// sanity-checks every value, returning nil for anything that doesn't look right.
struct AbletonAnalysis {
    var bpm: Double?
    var timeSignature: (numerator: Int, denominator: Int)?

    static func sidecarURL(for mediaURL: URL) -> URL {
        mediaURL.deletingLastPathComponent()
            .appendingPathComponent(mediaURL.lastPathComponent + ".asd")
    }

    static func load(for mediaURL: URL) -> AbletonAnalysis? {
        guard let data = try? Data(contentsOf: sidecarURL(for: mediaURL), options: .mappedIfSafe)
        else { return nil }
        // Field names come first in the file, values after; values start at the
        // header of the first clip value (LoopStart).
        guard let values = data.range(of: valuesHeader) else { return nil }
        let result = AbletonAnalysis(
            bpm: bpm(in: data, from: values.upperBound),
            timeSignature: timeSignature(in: data, from: values.upperBound)
        )
        return result.bpm == nil && result.timeSignature == nil ? nil : result
    }

    private static let valuesHeader = Data([0x10]) + Data("RemoteableDouble".utf8)
        + Data([1, 0, 0, 0, 5, 0, 0, 0]) + Data("Value".utf16LittleEndian) + Data([0x17])

    /// Warp markers pair a position in seconds with a position in beats; the first
    /// non-zero marker gives the clip tempo.
    private static func bpm(in data: Data, from valuesStart: Int) -> Double? {
        // Length-prefixed "WarpMarker", then an Int32 index, then two Float64s (sec, beat).
        let tag = Data([0x0A]) + Data("WarpMarker".utf8)
        var searchStart = valuesStart
        while let range = data.range(of: tag, in: searchStart..<data.endIndex) {
            searchStart = range.upperBound
            let base = range.upperBound + 4
            guard base + 16 <= data.endIndex else { break }
            let seconds = data.float64(at: base)
            let beats = data.float64(at: base + 8)
            guard seconds > 0, beats > 0, seconds.isFinite, beats.isFinite else { continue }
            let bpm = beats / seconds * 60
            return (20...999).contains(bpm) ? bpm : nil
        }
        return nil
    }

    /// Clip values follow the values header in a fixed layout:
    /// 6 Float64 (loop/offset markers), 4 Bool, 4 Float32, warp-mode Int32,
    /// 8 warp-setting fields (4 bytes each), then numerator/denominator as Float32.
    private static func timeSignature(in data: Data, from valuesStart: Int) -> (numerator: Int, denominator: Int)? {
        let offset = valuesStart + 48 + 4 + 16 + 4 + 32
        guard offset + 8 <= data.endIndex else { return nil }
        let numerator = data.float32(at: offset)
        let denominator = data.float32(at: offset + 4)
        guard (1...99).contains(numerator), numerator == numerator.rounded(),
              [1, 2, 4, 8, 16, 32].contains(denominator)
        else { return nil }
        return (Int(numerator), Int(denominator))
    }
}

private extension String {
    var utf16LittleEndian: [UInt8] {
        utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }
}

private extension Data {
    func float64(at index: Index) -> Double {
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(self[index + i]) << (8 * UInt64(i)) }
        return Double(bitPattern: bits)
    }

    func float32(at index: Index) -> Float {
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(self[index + i]) << (8 * UInt32(i)) }
        return Float(bitPattern: bits)
    }
}
