import SwiftUI

struct CustomRepeatPicker: View {
    @Binding var selection: Set<Int>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var diameter = 36
    private let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var summary: String {
        switch selection {
        case Set(1...7): "Every day"
        case Set(2...6): "Weekdays"
        case Set([1, 7]): "Weekends"
        case []: "Select at least one day"
        default: selection.sorted().map { String(days[$0 - 1].prefix(3)) }.joined(separator: ", ")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Days")
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selection)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(1...7, id: \.self) { day in weekdayButton(day) }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: max(44, diameter + 8)), spacing: 4)], spacing: 8) {
                    ForEach(1...7, id: \.self) { day in weekdayButton(day) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weekdayButton(_ day: Int) -> some View {
        let selected = selection.contains(day)
        return Button {
            if selected { selection.remove(day) }
            else { selection.insert(day) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(String(days[day - 1].prefix(1)))
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(selected ? Color.accentColor : nil).interactive(), in: .circle)
        .frame(minWidth: max(44, diameter + 8), maxWidth: .infinity, minHeight: max(44, diameter + 8))
        .accessibilityLabel(days[day - 1])
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
