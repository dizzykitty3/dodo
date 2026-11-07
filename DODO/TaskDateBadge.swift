import SwiftUI

enum DateBadgeOrder: String, CaseIterable {
    case yearFirst = "Year, Month, Day"
    case monthFirst = "Month, Day, Year"
    case dayFirst = "Day, Month, Year"
}

enum DateBadgeSeparator: String, CaseIterable {
    case dash = "-", slash = "/", dot = "."
}

struct DateBadgePreferences: DynamicProperty {
    static func initializeFromSystem() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "dateBadgeInitialized") else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let pattern = formatter.dateFormat ?? "yyyy-MM-dd"
        let fields = pattern.replacingOccurrences(of: "'[^']*'", with: "", options: .regularExpression)
        let order: DateBadgeOrder
        switch fields.first(where: { "yYMLd".contains($0) }) {
        case "d": order = .dayFirst
        case "M", "L": order = .monthFirst
        default: order = .yearFirst
        }
        let separator = DateBadgeSeparator.allCases.first { fields.contains($0.rawValue) } ?? .dash
        defaults.set(order.rawValue, forKey: "dateBadgeOrder")
        defaults.set(separator.rawValue, forKey: "dateBadgeSeparator")
        defaults.set(pattern, forKey: "dateBadgeInitialPattern")
        defaults.set(order.rawValue, forKey: "dateBadgeInitialOrder")
        defaults.set(separator.rawValue, forKey: "dateBadgeInitialSeparator")
        defaults.set(true, forKey: "dateBadgeInitialized")
    }

    @AppStorage("dateBadgeOrder") var order = DateBadgeOrder.yearFirst
    @AppStorage("dateBadgeSeparator") var separator = DateBadgeSeparator.dash
    @AppStorage("dateBadgeShowsCurrentYear") var showsCurrentYear = true

    func display(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        let year = parts[0], month = parts[1], date = parts[2]
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: .now)
        let includeYear = showsCurrentYear || Int(year) != currentYear
        let defaults = UserDefaults.standard
        if order.rawValue == defaults.string(forKey: "dateBadgeInitialOrder"),
           separator.rawValue == defaults.string(forKey: "dateBadgeInitialSeparator"),
           let pattern = defaults.string(forKey: "dateBadgeInitialPattern"),
           let value = try? TaskRecord.dayFormat.parseStrategy.parse(day) {
            let formatter = DateFormatter()
            // Keep the original field widths and literals when using the imported format.
            formatter.dateFormat = includeYear ? pattern : pattern.replacingOccurrences(
                of: #"^[^MdL]*[yY]+[^MdL]*|[^MdL]*[yY]+[^MdL]*$"#, with: "", options: .regularExpression)
            return formatter.string(from: value)
        }
        let fields: [Substring]
        switch order {
        case .yearFirst: fields = includeYear ? [year, month, date] : [month, date]
        case .monthFirst: fields = includeYear ? [month, date, year] : [month, date]
        case .dayFirst: fields = includeYear ? [date, month, year] : [date, month]
        }
        return fields.joined(separator: separator.rawValue)
    }
}

struct TaskDateBadge: View {
    let day: String
    private var preferences = DateBadgePreferences()

    var body: some View {
        Text(preferences.display(day))
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("Due " + day)
    }
}
