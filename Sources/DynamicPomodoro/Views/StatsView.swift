import AppKit
import SwiftUI

/// Focus hours per day over the last four calendar weeks, with break time
/// optionally stacked on top.
///
/// Deliberately a read-out and nothing else: no goal line, no streak, no
/// target, no comparison against last week, no congratulation. PURPOSE is
/// explicit that this is not a coaching app and that "more pomodoros" is not
/// the success metric — so the chart shows what happened and stops there.
/// It replaces the "load sessions.json into a notebook" step the README's
/// §10 review has always assumed.
///
/// The one control is the break-time button: a day at the desk is focus plus
/// the breaks between it, and that is the number that compares against a
/// working day. It adds a band to each bar and nothing else — still no line
/// to hit, still nothing said about the number it produces.
///
/// Its own window rather than a tab in the main one: the main window is
/// phase-driven and hides itself during focus, and a reference view that
/// vanishes when you start working is no use.
struct StatsView: View {
    let log: SessionLogStore

    @State private var weeks: [FocusWeek] = []
    /// Which read-out is on screen. Remembered across launches — it is how
    /// the chart is read, not a preference about how the app behaves, so it
    /// keeps its own key here rather than growing `Settings` or the four
    /// values `SettingsView` exposes (PURPOSE principle 5).
    @AppStorage("statsIncludeBreakTime") private var includeBreakTime = false
    private let calendar = Calendar.current
    private var measure: StatsMeasure { includeBreakTime ? .focusAndBreak : .focus }
    // Stats move on the scale of whole sessions, so a slow tick is plenty;
    // didBecomeActive below covers the case of App Nap throttling it.
    private let refresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            chart
            Divider()
            Text(footnote)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(measure.title)
                    .font(.title3.weight(.semibold))
                Text(windowRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            breakToggle
            Text(TimeFormat.duration(totalSeconds))
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
    }

    /// The whole control surface of this window: one click adds break time to
    /// every day, one click takes it away. The swatch is also the legend for
    /// the band the bars grow, so the button explains the chart it changes
    /// without a second row of chrome.
    private var breakToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { includeBreakTime.toggle() }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(includeBreakTime ? Self.breakFill : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                Text("Break time")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(includeBreakTime ? Color.primary : Color.secondary)
            .background(Capsule(style: .continuous).fill(Color.secondary.opacity(includeBreakTime ? 0.16 : 0.08)))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help(toggleHelp)
        .accessibilityLabel(Text("Break time"))
        .accessibilityValue(Text(toggleState))
    }

    private var toggleHelp: String {
        includeBreakTime ? "Show focus time only" : "Add break time to every day"
    }

    private var toggleState: String {
        includeBreakTime ? "shown" : "hidden"
    }

    private var footnote: String {
        let base = "A completed session counts its full length; an abandoned one counts only the time it ran."
        guard includeBreakTime else { return base }
        return base + " Break time is the breaks you took — a skipped one adds nothing."
    }

    private var windowRange: String {
        guard let first = weeks.first?.start, let last = weeks.last?.end else { return "" }
        return "\(Self.dayMonth.string(from: first)) – \(Self.dayMonth.string(from: last))"
    }

    private var totalSeconds: Int {
        weeks.reduce(0) { $0 + $1.seconds(measure) }
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
        let plotted = day.seconds(measure)
        return ZStack(alignment: .bottom) {
            // A day that happened gets a faint full-height slot, so a zero
            // reads as an empty column rather than as nothing at all. A day
            // that hasn't happened yet gets no slot: the week is genuinely
            // unfinished, and the gap says so more plainly than a third
            // shade of grey would. Kept light — at any weight where the
            // slots read as bars in their own right they also swallow the
            // gridlines behind them.
            if !day.isFuture {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.07))
                    .frame(width: Metrics.barWidth, height: Metrics.plotHeight)
            }
            if !day.isFuture, plotted > 0 {
                // The whole column in the lighter shade, with the focus
                // segment painted over it: the break time reads as a band
                // added on top rather than as a bar that quietly grew. In
                // the focus-only read-out the two are the same height and
                // the band is covered completely.
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.breakFill)
                    .frame(width: Metrics.barWidth, height: barHeight(plotted))
                if day.focusSeconds > 0 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isToday(day) ? Color.accentColor : Color.accentColor.opacity(0.75))
                        .frame(width: Metrics.barWidth,
                               height: min(barHeight(day.focusSeconds), barHeight(plotted)))
                }
            }
        }
        .frame(width: Metrics.barWidth, height: Metrics.plotHeight, alignment: .bottom)
        .help(tooltip(for: day))
    }

    /// A short session still gets a visible sliver: a day with twenty
    /// minutes on it should not read as a day off.
    private func barHeight(_ seconds: Int) -> CGFloat {
        max(2, height(forSeconds: seconds))
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
                    Text(TimeFormat.duration(week.seconds(measure)))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(week.seconds(measure) > 0 ? Color.secondary : Color.secondary.opacity(0.45))
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
        if totalSeconds == 0 {
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
        let peak = weeks.flatMap(\.days).map { $0.seconds(measure) }.max() ?? 0
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

    /// The band the bars grow when break time is included, and the swatch on
    /// the button that adds it — one constant so the legend cannot drift from
    /// the thing it labels.
    private static let breakFill = Color.accentColor.opacity(0.32)

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
        let split = "\(TimeFormat.duration(day.focusSeconds)) focus, "
            + "\(TimeFormat.duration(day.stats.breakSeconds)) break"
        guard includeBreakTime else { return "\(date) — \(split)" }
        return "\(date) — \(TimeFormat.duration(day.stats.totalSeconds)) total (\(split))"
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
