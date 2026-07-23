import AppKit
import CoreGraphics
import SwiftUI

final class DesktopPanel: NSPanel {
    private static let floatingKey = "floatAboveWindows"

    init(store: UsageStore) {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WidgetLayout.width,
                height: WidgetLayout.height(activeAgentCount: 0, range: store.range)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: DesktopWidgetView(store: store))
        setFrameAutosaveName("TokenScopeDesktopPanel")
        applySavedLevel()

        if !setFrameUsingName("TokenScopeDesktopPanel") {
            positionAtTopRight()
        }

    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var floatsAboveWindows: Bool {
        get { UserDefaults.standard.bool(forKey: Self.floatingKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.floatingKey)
            applySavedLevel()
        }
    }

    func show() {
        orderFrontRegardless()
    }

    private func applySavedLevel() {
        if floatsAboveWindows {
            level = .floating
        } else {
            let desktopIconLevel = CGWindowLevelForKey(.desktopIconWindow)
            level = NSWindow.Level(rawValue: Int(desktopIconLevel) - 1)
        }
    }

    private func positionAtTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - frame.width - 28,
            y: visible.maxY - frame.height - 28
        )
        setFrameOrigin(origin)
    }

    func updateLayout(activeAgentCount: Int, range: UsageRange) {
        let newHeight = WidgetLayout.height(activeAgentCount: activeAgentCount, range: range)
        guard abs(frame.height - newHeight) > 0.5 else { return }

        let topEdge = frame.maxY
        setContentSize(NSSize(width: WidgetLayout.width, height: newHeight))
        setFrameOrigin(NSPoint(x: frame.minX, y: topEdge - frame.height))
    }
}
