import SwiftUI

struct CalendarView: View {
    @Binding var selectedDate: Date
    let timeZone: TimeZone
    var cellHeight: CGFloat = 32
    @State private var displayMonth: Date

    init(selectedDate: Binding<Date>, timeZone: TimeZone = .current, cellHeight: CGFloat = 32) {
        _selectedDate = selectedDate
        self.timeZone = timeZone
        self.cellHeight = cellHeight
        _displayMonth = State(initialValue: selectedDate.wrappedValue)
    }

    private var calendar: Calendar {
        ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
    }

    private var weekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        return formatter.veryShortStandaloneWeekdaySymbols
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // 月ナビゲーションヘッダー
            HStack {
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: AppIcons.Controls.chevronLeft)
                        .font(.body.bold())
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("前の月")

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: AppIcons.Controls.chevronRight)
                        .font(.body.bold())
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("次の月")
            }

            // 曜日ヘッダー
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            // 日付グリッド（7列）
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: Spacing.xs / 4
            ) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day = day {
                        CalendarDayCell(
                            date: day,
                            timeZone: timeZone,
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            isToday: ObservationTimeZone.isDateInToday(day, timeZone: timeZone),
                            cellHeight: cellHeight,
                            onTap: { selectedDate = day }
                        )
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight)
                    }
                }
            }
        }
        .padding(Spacing.xs)
        .frame(maxWidth: .infinity)
        .onChange(of: selectedDate) {
            if !calendar.isDate(selectedDate, equalTo: displayMonth, toGranularity: .month) {
                displayMonth = selectedDate
            }
        }
    }

    // 当月の日付配列（先頭は空白セル nil で埋める）
    private var days: [Date?] {
        guard
            let range = calendar.range(of: .day, in: .month, for: displayMonth),
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth))
        else { return [] }

        let weekday = calendar.component(.weekday, from: firstDay)  // 1=日, 7=土
        var result: [Date?] = Array(repeating: nil, count: weekday - 1)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                result.append(date)
            }
        }
        return result
    }

    private var monthTitle: String {
        DateFormatters.monthTitleString(from: displayMonth, timeZone: timeZone)
    }

    private func shiftMonth(by value: Int) {
        displayMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) ?? displayMonth
    }
}

struct CalendarDayCell: View {
    let date: Date
    let timeZone: TimeZone
    let isSelected: Bool
    let isToday: Bool
    var cellHeight: CGFloat = 32
    let onTap: () -> Void

    private var calendar: Calendar {
        ObservationTimeZone.gregorianCalendar(timeZone: timeZone)
    }
    private var dayNumber: Int { calendar.component(.day, from: date) }

    private var accessibilityDateLabel: String {
        var label = DateFormatters.fullDateString(from: date, timeZone: timeZone)
        if isSelected { label += "、" + L10n.tr("選択中") }
        if isToday { label += "、" + L10n.tr("今日") }
        return label
    }

    var body: some View {
        Button(action: onTap) {
            Text("\(dayNumber)")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: cellHeight)
                .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : Color.primary)
                .background(
                    Circle()
                        .fill(
                            isSelected ? Color.accentColor :
                            isToday    ? Color.accentColor.opacity(0.15) :
                                         Color.clear
                        )
                        .padding(1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDateLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CalendarView(selectedDate: .constant(Date()))
        .frame(width: 280)
        .padding()
}
