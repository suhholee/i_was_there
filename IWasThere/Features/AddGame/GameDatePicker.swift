import SwiftUI

/// Date step calendar: month/year wheels confirm back to the day grid without advancing the add-game flow.
struct GameDatePicker: View {
    @Binding var selectedDate: Date
    @Binding var isPickingMonthYear: Bool
    @Binding var draftMonth: Int
    @Binding var draftYear: Int

    let maxDate: Date

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    init(
        selectedDate: Binding<Date>,
        isPickingMonthYear: Binding<Bool>,
        draftMonth: Binding<Int>,
        draftYear: Binding<Int>,
        maxDate: Date = .now
    ) {
        _selectedDate = selectedDate
        _isPickingMonthYear = isPickingMonthYear
        _draftMonth = draftMonth
        _draftYear = draftYear
        self.maxDate = maxDate
    }

    private var monthStart: Date {
        calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1)) ?? selectedDate
    }

    private var monthYearLabel: String {
        "\(monthStart.formatted(.dateTime.month(.wide))) \(YearFormat.string(draftYear))"
    }

    private var yearOptions: [Int] {
        let currentYear = calendar.component(.year, from: maxDate)
        return Array((currentYear - 30)...currentYear).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isPickingMonthYear {
                monthYearPickers
            } else {
                dayPicker
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            syncDraft(from: newValue)
        }
    }

    static func syncDraft(from date: Date, draftMonth: inout Int, draftYear: inout Int) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.month, .year], from: date)
        if let month = parts.month { draftMonth = month }
        if let year = parts.year { draftYear = year }
    }

    static func applyMonthYear(
        selectedDate: inout Date,
        draftMonth: Int,
        draftYear: Int,
        maxDate: Date = .now
    ) {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: selectedDate)
        let monthStart = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: 1)) ?? selectedDate
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let clampedDay = min(day, daysInMonth)

        if let candidate = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: clampedDay)) {
            selectedDate = min(candidate, maxDate)
        }
    }

    private var monthYearPickers: some View {
        HStack(spacing: 0) {
            Picker("Month", selection: $draftMonth) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthName(month)).tag(month)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Year", selection: $draftYear) {
                ForEach(yearOptions, id: \.self) { year in
                    Text(YearFormat.string(year)).tag(year)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 180)
    }

    private var dayPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                syncDraft(from: selectedDate)
                isPickingMonthYear = true
            } label: {
                HStack {
                    Text(monthYearLabel)
                        .font(.headline)
                        .foregroundStyle(DesignTokens.primaryText)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText)
                }
            }
            .buttonStyle(.plain)

            dayGrid
        }
    }

    private var dayGrid: some View {
        let days = daysInDisplayedMonth
        let leadingBlanks = leadingBlankDays

        return VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText)
                        .frame(maxWidth: .infinity)
                }

                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 36)
                }

                ForEach(days, id: \.self) { day in
                    dayButton(day)
                }
            }
        }
        .padding(12)
        .background(DesignTokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayButton(_ day: Int) -> some View {
        let date = calendar.date(from: DateComponents(year: draftYear, month: draftMonth, day: day))
        let isSelected = date.map { calendar.isDate($0, inSameDayAs: selectedDate) } ?? false
        let isFuture = date.map { $0 > maxDate } ?? true
        let isDisabled = isFuture

        return Button {
            guard let date, !isDisabled else { return }
            selectedDate = date
        } label: {
            Text("\(day)")
                .font(.subheadline.weight(isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(isDisabled ? DesignTokens.secondaryText.opacity(0.35) : DesignTokens.primaryText)
                .background(isSelected ? DesignTokens.accent : Color.clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var daysInDisplayedMonth: [Int] {
        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return Array(1...count)
    }

    private var leadingBlankDays: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func syncDraft(from date: Date) {
        Self.syncDraft(from: date, draftMonth: &draftMonth, draftYear: &draftYear)
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        components.day = 1
        let date = calendar.date(from: components) ?? selectedDate
        return date.formatted(.dateTime.month(.wide))
    }
}
