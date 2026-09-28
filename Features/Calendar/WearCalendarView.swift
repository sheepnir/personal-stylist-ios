import SwiftUI

/// Sprint 9 wear calendar (#123, ADR-0004). Read-only view over `model.wearEvents`:
/// no writes, no generation, no model calls. Days use `Calendar.current`, like `WearLogging`.
struct WearCalendarView: View {
    @ObservedObject var model: LoopDemoModel
    /// Opens a garment that still exists (the Wardrobe tab owns garment detail).
    var onOpenGarment: (StubGarment) -> Void = { _ in }

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var visibleMonth: WearCalendar.Month?
    @State private var selectedDay: WearCalendar.Day?

    private var now: Date { Date() }
    private var today: WearCalendar.Day { WearCalendar.day(for: now, calendar: calendar) }
    private var month: WearCalendar.Month { visibleMonth ?? WearCalendar.month(containing: now, calendar: calendar) }
    private var selection: WearCalendar.Day { selectedDay ?? today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthHeader
                weekdayHeader
                dayGrid
                Divider()
                dayDetail
            }
            .padding()
        }
        .navigationTitle(WearCalendarCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(WearCalendarCopy.today) { showToday() }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityHint(WearCalendarCopy.todayHint)
                    .accessibilityIdentifier("calendar.today")
            }
        }
    }

    // MARK: - Month grid

    private var monthHeader: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(WearCalendarCopy.previousMonth)
            .accessibilityIdentifier("calendar.previousMonth")
            Spacer()
            Text(monthTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(WearCalendarCopy.nextMonth)
            .accessibilityIdentifier("calendar.nextMonth")
        }
    }

    private var weekdayHeader: some View {
        let symbols = WearCalendar.orderedWeekdaySymbols(calendar: calendar)
        let names = WearCalendar.orderedWeekdayNames(calendar: calendar)
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(index < names.count ? names[index] : symbol)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dayGrid: some View {
        let marked = WearCalendar.markedDays(in: month, events: model.wearEvents, calendar: calendar)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear
                    .frame(minHeight: 44)
                    .accessibilityHidden(true)
            }
            ForEach(month.days, id: \.self) { day in
                dayCell(day, hasRecord: marked.contains(day))
            }
        }
    }

    private func dayCell(_ day: WearCalendar.Day, hasRecord: Bool) -> some View {
        let isSelected = day == selection
        let isToday = day == today
        let date = WearCalendar.startDate(of: day, calendar: calendar) ?? now
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.body.monospacedDigit())
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Circle()
                    .fill(hasRecord ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            }
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            WearCalendarCopy.dayAccessibility(date, hasRecord: hasRecord, isToday: isToday, locale: locale, calendar: calendar)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Selected day

    @ViewBuilder
    private var dayDetail: some View {
        let records = WearCalendar.records(on: selection, events: model.wearEvents, calendar: calendar)
        let date = WearCalendar.startDate(of: selection, calendar: calendar) ?? now
        VStack(alignment: .leading, spacing: 12) {
            Text(WearCalendarCopy.dayTitle(date, locale: locale, calendar: calendar))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(WearCalendarCopy.noOutfitRecorded)
                        .font(.body)
                    Text(WearCalendarCopy.noOutfitHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("calendar.empty")
            } else {
                if records.count > 1 {
                    Text(WearCalendarCopy.multipleLooksNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(records) { record in
                    recordCard(record)
                }
                Text(WearCalendarCopy.historyNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func recordCard(_ record: StubWearEvent) -> some View {
        let resolved = WearCalendar.resolve(record, garments: model.garments, id: \.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(WearCalendarCopy.loggedAt(record.wornOn, locale: locale, calendar: calendar))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(resolved.available) { garment in
                Button {
                    onOpenGarment(garment)
                } label: {
                    HStack(spacing: 12) {
                        FixtureImageView(garment: garment, height: 56, presentation: .tiny)
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(garment.displayName)
                                .font(.body)
                                .foregroundStyle(Color.primary)
                            Text(garment.slot.displayLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(garment.displayName), \(garment.slot.displayLabel)")
                .accessibilityHint(WearCalendarCopy.openGarmentHint)
            }
            if resolved.missingCount > 0 {
                Label(WearCalendarCopy.missingItems(resolved.missingCount), systemImage: "questionmark.square.dashed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private var monthTitle: String {
        let first = WearCalendar.startDate(of: .init(year: month.year, month: month.month, day: 1), calendar: calendar) ?? now
        return WearCalendarCopy.monthTitle(first, locale: locale, calendar: calendar)
    }

    private func step(_ offset: Int) {
        visibleMonth = WearCalendar.month(month, offsetBy: offset, calendar: calendar)
    }

    private func showToday() {
        visibleMonth = WearCalendar.month(containing: Date(), calendar: calendar)
        selectedDay = WearCalendar.day(for: Date(), calendar: calendar)
    }
}
