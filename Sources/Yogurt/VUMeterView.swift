import SwiftUI

/// Stereo level meter, Live-style: bright RMS fill, a darker shade up to the live
/// peak, and a line at the highest recent peak; plus a dB scale and a numeric
/// readout of that held peak. Driven by an `AudioLevelMeter`.
struct VUMeterView: View {
    @ObservedObject var meter: AudioLevelMeter

    var body: some View {
        VUMeterContent(levels: meter.levels)
    }
}

/// Draws the meter for a given pair of levels (split out so it can be rendered
/// without live audio).
struct VUMeterContent: View {
    let levels: [ChannelLevel]

    private let barWidth: CGFloat = 18
    private let scaleWidth: CGFloat = 26

    var body: some View {
        let levels = levels.count >= 2 ? levels : [.silent, .silent]
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
        .padding(.top, 20)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Match AVPlayerView's audio-only placeholder grey; force dark so labels stay legible.
        .background(Theme.mediaSurface)
        .environment(\.colorScheme, .dark)
    }

    private func readout(_ level: ChannelLevel) -> some View {
        // Round before formatting so -0.4 reads "0", not "-0".
        Text(level.hold <= MeterMetrics.floorDB ? "-∞" : "\(Int(level.hold.rounded()))")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(level.hold >= MeterMetrics.clipDB ? Color.red : MeterMetrics.labelColor)
    }
}

/// Shared dB↔fraction mapping and color zones so bars and the scale stay aligned.
private enum MeterMetrics {
    static let floorDB: Float = AudioLevelMeter.floorDB
    static let clipDB: Float = -1
    /// Scale ticks, scale numbers and peak readouts — solid enough to read on the grey surface.
    static let labelColor = Color.white.opacity(0.75)
    static let ticks: [Int] = Array(stride(from: 0, through: -60, by: -12))
    /// Every other tick gets a number, starting at 0.
    static func isLabeled(_ db: Int) -> Bool { db % 24 == 0 }

    /// Fraction 0 (floor) ... 1 (0 dBFS) up the bar.
    static func fraction(_ db: Float) -> CGFloat {
        let clamped = min(0, max(floorDB, db))
        return CGFloat((clamped - floorDB) / (0 - floorDB))
    }

    /// Bottom→top colour ramp, blended smoothly: solid green through the quiet
    /// range, then green→yellow→orange→red approaching 0 dBFS.
    static let gradient = LinearGradient(
        stops: [
            .init(color: .green, location: 0.0),
            .init(color: .green, location: fraction(-24)),
            .init(color: .yellow, location: fraction(-12)),
            .init(color: .orange, location: fraction(-6)),
            .init(color: .red, location: fraction(-1)),
            .init(color: .red, location: 1.0),
        ],
        startPoint: .bottom,
        endPoint: .top
    )
}

/// A single vertical bar: dim track, darker live-peak shade, bright RMS fill,
/// peak-hold line.
private struct MeterBar: View {
    let level: ChannelLevel

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let rmsFrac = MeterMetrics.fraction(level.rms)
            let peakFrac = MeterMetrics.fraction(level.peak)
            let holdFrac = MeterMetrics.fraction(level.hold)
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.3))

                // Live peak: the same ramp, dimmed, behind the RMS fill.
                Rectangle()
                    .fill(MeterMetrics.gradient)
                    .opacity(0.4)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: h * peakFrac)
                    }

                Rectangle()
                    .fill(MeterMetrics.gradient)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: h * rmsFrac)
                    }

                // Highest recent peak. Hidden at the floor so silence shows an empty bar.
                if level.hold > MeterMetrics.floorDB {
                    Rectangle()
                        .fill(level.hold >= MeterMetrics.clipDB ? Color.red : Color.white.opacity(0.9))
                        .frame(height: 2)
                        // Centre on the level, kept inside the bar like the end ticks.
                        .offset(y: -min(max(h * holdFrac, 1), h - 1) + 1)
                }
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

                if MeterMetrics.isLabeled(db) {
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
}
