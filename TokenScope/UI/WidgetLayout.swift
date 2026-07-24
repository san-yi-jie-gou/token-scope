import CoreGraphics

enum WidgetLayout {
    static let width: CGFloat = 380
    static let energyCoreHeight: CGFloat = 210
    static let monthChartHeight: CGFloat = 78
    static let sourceRowHeight: CGFloat = 36
    static let footerHeight: CGFloat = 35

    private static let fixedHeight: CGFloat = 310

    static func height(activeAgentCount: Int, range: UsageRange) -> CGFloat {
        let chartHeight = range == .month && activeAgentCount > 0 ? monthChartHeight : 0
        return fixedHeight + sourceRowsHeight(activeAgentCount: activeAgentCount) + chartHeight
    }

    static func sourceRowsHeight(activeAgentCount: Int) -> CGFloat {
        CGFloat(max(1, activeAgentCount)) * sourceRowHeight
    }
}
