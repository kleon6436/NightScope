import SwiftUI

struct CalendarView: View {
    @Binding var selectedDate: Date
    @State private var displayMonth: Date

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        _displayMonth = State(initialValue: selectedDate.wrappedValue)
    }

    private let calendar = Calendar.current
    private let weekdayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // 月ナビゲーションヘッダー
            HStack {
                Button { shiftMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("前の月")

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button { shiftMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.bold())
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
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(day),
                            onTap: { selectedDate = day }
                        )
                    } else {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 32)
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
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f.string(from: displayMonth)
    }

    private func shiftMonth(by value: Int) {
        displayMonth = calendar.date(byAdding: .month, value: value, to: displayMonth) ?? displayMonth
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void

    private let calendar = Calendar.current
    private var dayNumber: Int { calendar.component(.day, from: date) }

    private var accessibilityDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        var label = formatter.string(from: date)
        if isSelected { label += "、選択中" }
        if isToday { label += "、今日" }
        return label
    }

    var body: some View {
        Text("\(dayNumber)")
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 32)
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
            .onTapGesture { onTap() }
            .accessibilityLabel(accessibilityDateLabel)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CalendarView(selectedDate: .constant(Date()))
        .frame(width: 280)
        .padding()
}
