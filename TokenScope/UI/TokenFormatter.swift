import Foundation

enum TokenFormatter {
    static func compact(_ value: Int64) -> String {
        let absolute = Double(abs(value))
        let sign = value < 0 ? "-" : ""

        switch absolute {
        case 1_000_000_000...:
            return sign + formatted(absolute / 1_000_000_000) + "B"
        case 1_000_000...:
            return sign + formatted(absolute / 1_000_000) + "M"
        case 1_000...:
            return sign + formatted(absolute / 1_000) + "K"
        default:
            return value.formatted()
        }
    }

    static func full(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func formatted(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

