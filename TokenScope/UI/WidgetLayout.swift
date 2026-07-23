import CoreGraphics

enum WidgetLayout {
    static let width: CGFloat = 380
    private static let monthChartHeight: CGFloat = 106

    static func height(activeAgentCount: Int, range: UsageRange) -> CGFloat {
        let chartHeight = range == .month && activeAgentCount > 0 ? monthChartHeight : 0
        return 228 + CGFloat(max(1, activeAgentCount)) * 29 + chartHeight
    }
}
