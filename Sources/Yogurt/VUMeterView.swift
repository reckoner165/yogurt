import SwiftUI

/// Stereo level meter: two color-coded bars (RMS fill + peak-hold line), an
/// evenly spaced dB scale, and a numeric peak readout. Driven by an `AudioLevelMeter`.
struct VUMeterView: View {
    @ObservedObject var meter: AudioLevelMeter

    private let barWidth: CGFloat = 18
    private let scaleWidth: CGFloat = 26

    var body: some View {
        let levels = meter.levels.count >= 2 ? meter.levels : [.silent, .silent]
        // Bars and readouts are centered; the scale hangs off the bars' left edge.
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                MeterBar(level: levels[0]).frame(width: barWidth)
                MeterBar(level: levels[1]).frame(width: barWidth)
            }
            .overlay(alignment: .leading) {
                ScaleColumn()
                    .frame(width: scaleWidth)
                    .offset(x: -(scaleWidth + 2))
            }

            HStack(spacing: 6) {
                readout(levels[0]).frame(width: barWidth)
                readout(levels[1]).frame(width: barWidth)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Match AVPlayerView's audio-only placeholder grey; force dark so labels stay legible.
        .background(Theme.mediaSurface)
        .environment(\.colorScheme, .dark)
    }

    private func readout(_ level: ChannelLevel) -> some View {
        Text(level.peak <= MeterMetrics.floorDB ? "-∞" : String(format: "%.0f", level.peak))
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(level.peak >= MeterMetrics.clipDB ? Color.red : MeterMetrics.labelColor)
    }
}

/// Shared dB↔fraction mapping and color zones so bars and the scale stay aligned.
private enum MeterMetrics {
    static let floorDB: Float = AudioLevelMeter.floorDB
    static let clipDB: Float = -1
    /// Scale ticks, scale numbers and peak readouts — near-black ink on the grey surface.
    static let labelColor = Color(white: 0.1)
    static let ticks: [Int] = Array(stride(from: 0, through: -60, by: -10))

    /// Fraction 0 (floor) ... 1 (0 dBFS) up the bar.
    static func fraction(_ db: Float) -> CGFloat {
        let clamped = min(0, max(floorDB, db))
        return CGFloat((clamped - floorDB) / (0 - floorDB))
    }

    /// Bottom→top gradient: green up to -18 dB, yellow to -6 dB, red above.
    static let gradient = LinearGradient(
        stops: [
            .init(color: .green, location: 0.0),
            .init(color: .green, location: fraction(-18)),
            .init(color: .yellow, location: fraction(-18) + 0.01),
            .init(color: .yellow, location: fraction(-6)),
            .init(color: .red, location: fraction(-6) + 0.01),
            .init(color: .red, location: 1.0),
        ],
        startPoint: .bottom,
        endPoint: .top
    )
}

/// A single vertical bar: dim track, gradient RMS fill, peak-hold line.
private struct MeterBar: View {
    let level: ChannelLevel

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let rmsFrac = MeterMetrics.fraction(level.rms)
            let peakFrac = MeterMetrics.fraction(level.peak)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.3))

                Rectangle()
                    .fill(MeterMetrics.gradient)
                    .frame(maxHeight: .infinity)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: h * rmsFrac)
                    }

                Rectangle()
                    .fill(level.peak >= MeterMetrics.clipDB ? Color.red : Color.white.opacity(0.9))
                    .frame(height: 2)
                    .offset(y: -h * peakFrac + 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// Calibration column: a short tick at each dB mark's exact height, with its label
/// beside it. The end ticks sit just inside the bar; their labels are nudged only
/// enough to keep the digits (not the full line box) within the bar's range.
private struct ScaleColumn: View {
    private let tickLength: CGFloat = 4
    private let labelGap: CGFloat = 2
    private let tickThickness: CGFloat = 1
    /// Half the visible digit height at 8pt — tighter than the text's line box.
    private let digitHalfHeight: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let labelWidth = w - tickLength - labelGap
            ForEach(MeterMetrics.ticks, id: \.self) { db in
                let y = h * (1 - MeterMetrics.fraction(Float(db)))
                let tickY = min(max(y, tickThickness / 2), h - tickThickness / 2)

                Rectangle()
                    .fill(MeterMetrics.labelColor)
                    .frame(width: tickLength, height: tickThickness)
                    .position(x: w - tickLength / 2, y: tickY)

                Text("\(db)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(MeterMetrics.labelColor)
                    .frame(width: labelWidth, alignment: .trailing)
                    .position(
                        x: labelWidth / 2,
                        y: min(max(y, digitHalfHeight), h - digitHalfHeight)
                    )
            }
        }
    }
}
