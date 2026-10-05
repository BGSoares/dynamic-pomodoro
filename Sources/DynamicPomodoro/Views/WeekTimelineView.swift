import SwiftUI

/// The stats window's timeline page: last week and this week, Monday to
/// Sunday, one row per day, with every focus session and break drawn at the
/// wall-clock hour it actually ran.
///
/// A timesheet, not a score. The question it answers is when the day
/// started, where it paused and when it stopped – which is what hours
/// reported at work ask for, and what neither the totals page nor a bare
/// `sessions.json` can show at a glance. Same posture as the totals page: a
/// readout and nothing else. No target hours, no comparison, nothing said
/// about the shape it shows.
///
/// Both weeks share one axis so switching between them doesn't rescale the
/// day under the eye.
struct WeekTimelineView: View {
    /// Oldest first – `WeekTimeline.weeks`. Last week, then this week.
    let weeks: [TimelineWeek]
    /// Minutes since midnight – `WeekTimeline.axis`.
    let axis: ClosedRange<Int>
    let calendar: Calendar

    private enum WeekChoice: Hashable {
        case last, this
    }

    /// Opens on this week every time; the choice is a glance, not a
    /// preference, so it is not remembered.
    @State private var choice: WeekChoice = .this

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let week {
                timeline(for: week)
                    .overlay { emptyStateLabel(for: week) }
                legend
            }
            Divider()
            Text("Each day is labelled with the first start and the last end of what was logged. A skipped break is not drawn – you kept working. Hover a block for its exact times.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var week: TimelineWeek? {
        switch choice {
        case .this: return weeks.last
        case .last: return weeks.count >= 2 ? weeks[weeks.count - 2] : nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice == .this ? "This week" : "Last week")
                    .font(.title3.weight(.semibold))
                Text(weekRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Week", selection: $choice) {
                Text("Last week").tag(WeekChoice.last)
                Text("This week").tag(WeekChoice.this)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private var weekRange: String {
        guard let week else { return "" }
        return "\(Self.dayMonth.string(from: week.start)) – \(Self.dayMonth.string(from: week.end))"
    }

    // MARK: - Timeline

    private func timeline(for week: TimelineWeek) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            indentedRow { hourLabels }
            ZStack(alignment: .topLeading) {
                indentedRow { gridLines }
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    ForEach(week.days) { day in row(for: day) }
                }
            }
        }
    }

    /// Lines a row up under the track, past the day-label gutter.
    private func indentedRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Metrics.gutterGap) {
            Color.clear.frame(width: Metrics.gutterWidth, height: 1)
            content()
        }
    }

    private func row(for day: TimelineDay) -> some View {
        HStack(alignment: .center, spacing: Metrics.gutterGap) {
            // Pinned to the row height so the label column can never make
            // a row taller than its track – the gridlines behind the rows
            // are sized from `rowsHeight` and must end where the rows end.
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.weekdayDay.string(from: day.date))
                    .font(.system(size: 11, weight: isToday(day) ? .semibold : .regular))
                    .foregroundStyle(labelColor(for: day))
                Text(spanText(for: day))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(day.span == nil ? Color.secondary.opacity(0.45) : Color.secondary)
            }
            .frame(width: Metrics.gutterWidth, height: Metrics.rowHeight, alignment: .leading)

            ZStack(alignment: .leading) {
                // A day that happened gets a faint full-width slot, so an
                // empty day reads as an empty row rather than as nothing.
                // A day that hasn't happened yet gets no slot (the same
                // convention as the totals page).
                if !day.isFuture {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.secondary.opacity(0.07))
                        .frame(width: Metrics.trackWidth, height: Metrics.rowHeight)
                }
                ForEach(day.blocks) { block in
                    blockView(block, isToday: isToday(day))
                        .offset(x: x(forSecond: block.startSecond))
                }
            }
            .frame(width: Metrics.trackWidth, height: Metrics.rowHeight, alignment: .leading)
        }
    }

    /// Completed focus is solid, abandoned focus hollow (it ran, it wasn't
    /// finished), a break the lighter band the totals page also uses – one
    /// legend across both pages. Breaks sit a little shorter than the focus
    /// blocks they separate, so a row reads as work with pauses in it.
    @ViewBuilder
    private func blockView(_ block: TimelineBlock, isToday: Bool) -> some View {
        let width = max(Metrics.minBlockWidth, x(forSecond: block.endSecond) - x(forSecond: block.startSecond))
        let focusColor = isToday ? Color.accentColor : Color.accentColor.opacity(0.75)
        Group {
            switch block.kind {
            case .focusCompleted:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(focusColor)
                    .frame(width: width, height: Metrics.rowHeight)
            case .focusAbandoned:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(focusColor, lineWidth: 1)
                    .frame(width: width, height: Metrics.rowHeight)
            case .breakCompleted:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(StatsView.breakFill)
                    .frame(width: width, height: Metrics.rowHeight - 8)
            case .breakSkipped:
                EmptyView()
            }
        }
        .help(tooltip(for: block))
    }

    @ViewBuilder
    private func emptyStateLabel(for week: TimelineWeek) -> some View {
        if week.isEmpty {
            Text(choice == .this ? "Nothing logged this week." : "Nothing logged last week.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, Metrics.gutterWidth + Metrics.gutterGap)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Focus") {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.accentColor.opacity(0.75))
            }
            legendItem("Abandoned") {
                RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
            }
            legendItem("Break") {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(StatsView.breakFill)
            }
        }
        .padding(.leading, Metrics.gutterWidth + Metrics.gutterGap)
    }

    private func legendItem<Swatch: View>(_ label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Axis

    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Metrics.trackWidth, height: Metrics.axisHeight)
            ForEach(gridHours, id: \.self) { hour in
                Text("\(hour)")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: Metrics.hourLabelWidth, height: Metrics.axisHeight)
                    .offset(x: x(forMinute: hour * 60) - Metrics.hourLabelWidth / 2)
            }
        }
        .frame(width: Metrics.trackWidth, height: Metrics.axisHeight, alignment: .topLeading)
    }

    private var gridLines: some View {
        ZStack(alignment: .topLeading) {
            ForEach(gridHours, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 1, height: rowsHeight)
                    .offset(x: min(x(forMinute: hour * 60), Metrics.trackWidth - 1))
            }
        }
        .frame(width: Metrics.trackWidth, height: rowsHeight, alignment: .topLeading)
    }

    /// Every hour while the axis is a working day; every other hour once a
    /// stray early or late session has stretched it, so the labels keep
    /// their elbow room.
    private var gridHours: [Int] {
        let first = axis.lowerBound / 60
        let last = axis.upperBound / 60
        let step = last - first <= 12 ? 1 : 2
        return Array(stride(from: first, through: last, by: step))
    }

    private var rowsHeight: CGFloat {
        7 * Metrics.rowHeight + 6 * Metrics.rowSpacing
    }

    private func x(forMinute minute: Int) -> CGFloat {
        x(forSecond: minute * 60)
    }

    private func x(forSecond second: Int) -> CGFloat {
        let span = CGFloat((axis.upperBound - axis.lowerBound) * 60)
        guard span > 0 else { return 0 }
        let offset = CGFloat(second - axis.lowerBound * 60)
        return min(max(0, Metrics.trackWidth * offset / span), Metrics.trackWidth)
    }

    // MARK: - Per-day presentation

    private func isToday(_ day: TimelineDay) -> Bool {
        calendar.isDateInToday(day.date)
    }

    private func labelColor(for day: TimelineDay) -> Color {
        if isToday(day) { return .accentColor }
        if day.isFuture { return Color.secondary.opacity(0.45) }
        return calendar.isDateInWeekend(day.date) ? Color.secondary.opacity(0.45) : Color.secondary
    }

    private func spanText(for day: TimelineDay) -> String {
        guard let span = day.span else { return day.isFuture ? "" : "–" }
        return "\(clock(span.lowerBound))–\(clock(span.upperBound))"
    }

    private func tooltip(for block: TimelineBlock) -> String {
        let times = "\(clock(block.startSecond))–\(clock(block.endSecond))"
        let planned = block.entry.plannedMinutes
        switch block.kind {
        case .focusCompleted:
            return "Focus \(times) · \(planned) min"
        case .focusAbandoned:
            let ran = Int((Double(block.endSecond - block.startSecond) / 60).rounded())
            return "Focus \(times) · abandoned after \(ran) min of \(planned)"
        case .breakCompleted:
            return "Break \(times) · \(planned) min"
        case .breakSkipped:
            return ""
        }
    }

    /// 24-hour wall clock, same as the Settings window shows the workday.
    private func clock(_ secondsSinceMidnight: Int) -> String {
        TimeFormat.hhmm(min(secondsSinceMidnight, 24 * 3600 - 1) / 60)
    }

    // MARK: - Formatters

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static let weekdayDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f
    }()

    /// Fixed geometry, like the totals page: seven rows on a known track is
    /// a known size, and hard numbers keep the labels, the gridlines and the
    /// blocks on one grid without a layout pass.
    private enum Metrics {
        static let gutterWidth: CGFloat = 78
        static let gutterGap: CGFloat = 10
        static let trackWidth: CGFloat = 464
        static let rowHeight: CGFloat = 26
        static let rowSpacing: CGFloat = 6
        static let axisHeight: CGFloat = 12
        static let hourLabelWidth: CGFloat = 24
        /// A six-second abandon is still a thing that happened.
        static let minBlockWidth: CGFloat = 2
    }
}
