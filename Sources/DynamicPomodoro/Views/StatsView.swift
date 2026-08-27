import AppKit
import SwiftUI

/// Focus hours per day over the last four calendar weeks.
///
/// Deliberately a read-out and nothing else: no goal line, no streak, no
/// target, no comparison against last week, no congratulation. PURPOSE is
/// explicit that this is not a coaching app and that "more pomodoros" is not
/// the success metric — so the chart shows what happened and stops there.
/// It replaces the "load sessions.json into a notebook" step the README's
/// §10 review has always assumed.
///
/// Its own window rather than a tab in the main one: the main window is
/// phase-driven and hides itself during focus, and a reference view that
/// vanishes when you start working is no use.
struct StatsView: View {
    let log: SessionLogStore

    @State private var weeks: [FocusWeek] = []
    private let calendar = Calendar.current
    // Stats move on the scale of whole sessions, so a slow tick is plenty;
    // didBecomeActive below covers the case of App Nap throttling it.
    private let refresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            chart
            Divider()
            Text("A completed session counts its full length; an abandoned one counts only the time it ran.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 420, alignment: .topLeading)
        .onAppear { refreshData() }
        .onReceive(refresh) { _ in refreshData() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshData()
        }
    }

    private func refreshData() {
        weeks = log.focusWeeks(calendar: calendar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus per day")
                    .font(.title3.weight(.semibold))
                Text(windowRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(TimeFormat.duration(totalFocusSeconds))
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
    }

    private var windowRange: String {
        guard let first = weeks.first?.start, let last = weeks.last?.end else { return "" }
        return "\(Self.dayMonth.string(from: first)) – \(Self.dayMonth.string(from: last))"
    }

    private var totalFocusSeconds: Int {
        weeks.reduce(0) { $0 + $1.focusSeconds }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: Metrics.gutterGap) {
                axisLabels
                ZStack(alignment: .bottom) {
                    gridLines
                    dayGrid(alignment: .bottom) { bar(for: $0) }
                }
                .frame(width: chartWidth, height: Metrics.plotHeight)
                .overlay { emptyStateLabel }
            }
            indentedRow { dayGrid { dayNumber(for: $0) } }
            indentedRow { weekFooters }
        }
    }

    /// Lines up a row under the plot area, past the y-axis gutter.
    private func indentedRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Metrics.gutterGap) {
            Color.clear.frame(width: Metrics.gutterWidth, height: 1)
            content()
        }
    }

    /// One row on exactly the same week/day grid as the bars, so anything
    /// drawn beneath a column stays under its column.
    private func dayGrid<Cell: View>(
        alignment: VerticalAlignment = .top,
        @ViewBuilder cell: @escaping (FocusDay) -> Cell
    ) -> some View {
        HStack(alignment: alignment, spacing: Metrics.weekSpacing) {
            ForEach(weeks) { week in
                HStack(alignment: alignment, spacing: Metrics.daySpacing) {
                    ForEach(week.days) { day in
                        cell(day).frame(width: Metrics.barWidth)
                    }
                }
            }
        }
    }

    private func bar(for day: FocusDay) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.secondary.opacity(day.isFuture ? 0.05 : 0.12))
                .frame(width: Metrics.barWidth, height: Metrics.plotHeight)
            if !day.isFuture, day.focusSeconds > 0 {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isToday(day) ? Color.accentColor : Color.accentColor.opacity(0.75))
                    // A short session still gets a visible sliver: a day with
                    // twenty minutes on it should not read as a day off.
                    .frame(width: Metrics.barWidth, height: max(2, height(forSeconds: day.focusSeconds)))
            }
        }
        .frame(width: Metrics.barWidth, height: Metrics.plotHeight, alignment: .bottom)
        .help(tooltip(for: day))
    }

    private func dayNumber(for day: FocusDay) -> some View {
        Text("\(calendar.component(.day, from: day.date))")
            .font(.system(size: 9, weight: isToday(day) ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(labelColor(for: day))
    }

    private var weekFooters: some View {
        HStack(alignment: .top, spacing: Metrics.weekSpacing) {
            ForEach(weeks) { week in
                VStack(spacing: 1) {
                    Text(TimeFormat.duration(week.focusSeconds))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(week.focusSeconds > 0 ? Color.secondary : Color.secondary.opacity(0.45))
                    Text("\(Self.dayMonth.string(from: week.start)) – \(Self.dayMonth.string(from: week.end))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: Metrics.weekWidth)
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var emptyStateLabel: some View {
        if totalFocusSeconds == 0 {
            Text("No focus logged in these four weeks.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Axis

    private var axisLabels: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear.frame(width: Metrics.gutterWidth, height: Metrics.plotHeight)
            ForEach(gridHours, id: \.self) { hours in
                Text(hours == 0 ? "0" : "\(hours)h")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: Metrics.gutterWidth, height: Metrics.labelHeight, alignment: .trailing)
                    // Raise the label from the baseline to its gridline, then
                    // drop it half its own height so it centres on the line.
                    .offset(y: Metrics.labelHeight / 2 - height(forSeconds: hours * 3600))
            }
        }
    }

    private var gridLines: some View {
        ZStack(alignment: .bottom) {
            ForEach(gridHours, id: \.self) { hours in
                Rectangle()
                    .fill(Color.secondary.opacity(hours == 0 ? 0.30 : 0.12))
                    .frame(width: chartWidth, height: 1)
                    // Bottom-aligned, so a line sits in the 1pt band *below*
                    // its own value; clamped so the topmost one lands inside
                    // the plot rather than one point above it.
                    .offset(y: -min(height(forSeconds: hours * 3600), Metrics.plotHeight - 1))
            }
        }
        .frame(width: chartWidth, height: Metrics.plotHeight, alignment: .bottom)
    }

    /// Y-axis ceiling and gridline step. The ceiling is the tallest day
    /// rounded up to a whole number of gridline steps, with a two-hour
    /// floor — without it, a quiet fortnight redraws a twenty-minute day as
    /// a full-height bar and the chart flatters itself.
    private var scale: (ceilingSeconds: Int, stepHours: Int) {
        let peak = weeks.flatMap(\.days).map(\.focusSeconds).max() ?? 0
        let hours = max(2, Int(ceil(Double(peak) / 3600)))
        let step = hours <= 4 ? 1 : (hours <= 10 ? 2 : 4)
        let ceilingHours = Int(ceil(Double(hours) / Double(step))) * step
        return (ceilingHours * 3600, step)
    }

    private var gridHours: [Int] {
        Array(stride(from: 0, through: scale.ceilingSeconds / 3600, by: scale.stepHours))
    }

    private func height(forSeconds seconds: Int) -> CGFloat {
        let ceiling = scale.ceilingSeconds
        guard ceiling > 0 else { return 0 }
        return Metrics.plotHeight * CGFloat(seconds) / CGFloat(ceiling)
    }

    private var chartWidth: CGFloat {
        let n = CGFloat(max(weeks.count, 1))
        return n * Metrics.weekWidth + (n - 1) * Metrics.weekSpacing
    }

    // MARK: - Per-day presentation

    private func isToday(_ day: FocusDay) -> Bool {
        calendar.isDateInToday(day.date)
    }

    private func isWeekend(_ day: FocusDay) -> Bool {
        calendar.isDateInWeekend(day.date)
    }

    private func labelColor(for day: FocusDay) -> Color {
        if isToday(day) { return .accentColor }
        // Weekends dimmed so the week's rhythm is scannable — the bars stay
        // one colour, since dimming those would encode a judgement about
        // which days ought to count.
        return isWeekend(day) ? Color.secondary.opacity(0.45) : Color.secondary
    }

    private func tooltip(for day: FocusDay) -> String {
        let date = Self.fullDay.string(from: day.date)
        if day.isFuture { return date }
        if day.stats.totalSeconds == 0 { return "\(date) — nothing logged" }
        return "\(date) — \(TimeFormat.duration(day.focusSeconds)) focus, "
            + "\(TimeFormat.duration(day.stats.breakSeconds)) break"
    }

    // MARK: - Formatters

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let fullDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    /// Fixed geometry rather than a GeometryReader: 28 bars on a four-week
    /// grid is a known size, and hard numbers keep the bars, the day
    /// numbers and the week footers on one grid without a layout pass.
    private enum Metrics {
        static let barWidth: CGFloat = 14
        static let daySpacing: CGFloat = 3
        static let weekSpacing: CGFloat = 16
        static let plotHeight: CGFloat = 150
        static let gutterWidth: CGFloat = 26
        static let gutterGap: CGFloat = 8
        static let labelHeight: CGFloat = 12

        static var weekWidth: CGFloat { 7 * barWidth + 6 * daySpacing }
    }
}
