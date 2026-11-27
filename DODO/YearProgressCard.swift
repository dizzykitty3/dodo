import SwiftUI

struct YearProgressCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let progress = yearProgress(at: timeline.date)
            let percentage = progress.formatted(.percent.precision(.fractionLength(1)))
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Year Progress").font(.headline)
                    Spacer(minLength: 8)
                    Text(percentage)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: percentage)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.35, green: 0.65, blue: 0.43))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Year Progress")
            .accessibilityValue(percentage)
        }
    }

    private func yearProgress(at date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        guard let year = calendar.dateInterval(of: .year, for: date), year.duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(year.start) / year.duration))
    }
}
