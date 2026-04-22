import SwiftUI

/// Minimal line chart visualising the focus-duration curve across the workday.
/// Pure SwiftUI (no Charts dependency, to keep the deployment target at macOS 13).
struct CurvePreviewView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        let samples = DurationCurve.curveSamples(settings: settings, stepMinutes: 10)
        let minDur = settings.minFocusMinutes
        let maxDur = max(settings.maxFocusMinutes, minDur + 1)
        let startX = settings.workdayStartMinutes
        let endX = max(settings.workdayEndMinutes, startX + 1)

        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Axis bg
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))

                // Curve
                Path { path in
                    for (i, sample) in samples.enumerated() {
                        let x = CGFloat(sample.0 - startX) / CGFloat(endX - startX) * geo.size.width
                        let yNorm = CGFloat(sample.1 - minDur) / CGFloat(maxDur - minDur)
                        let y = geo.size.height - yNorm * geo.size.height * 0.85 - 8
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2)

                // Axis labels
                HStack {
                    Text(TimeFormat.hhmm(startX))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(TimeFormat.hhmm(settings.midpointMinutes))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(TimeFormat.hhmm(endX))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)

                VStack {
                    Text("\(maxDur) min")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(minDur) min")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
                .padding(.vertical, 4)
            }
        }
        .frame(height: 140)
    }
}
