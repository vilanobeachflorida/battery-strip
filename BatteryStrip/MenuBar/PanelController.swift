import AppKit
import SwiftUI

/// The glass panel that drops down from the menu bar item.
///
/// The SwiftUI content reports its height as it lays out, and this controller alone sizes the window,
/// always growing and shrinking downward from just under the menu bar.
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 340

    var onVisibilityChange: ((Bool) -> Void)?

    private let panel = StatusPanel()
    private let container = PanelContainerView()
    private var hostingView: NSHostingView<AnyView>?
    private var contentHeight: CGFloat = 0
    private var isResizePending = false
    private weak var anchor: NSStatusBarButton?
    private var lastClosed = Date.distantPast

    override init() {
        super.init()
        panel.contentView = container
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        container.onClickOutsideGlass = { [weak self] in self?.close() }
    }

    func setContent(_ content: some View) {
        // Scrolls only on screens too short for everything, such as with Details open on a small display.
        let root = ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                // Reported during layout, the moment the content changes size, so the window keeps up.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] height in
                    self?.contentHeightChanged(height)
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        // If the window and content are ever a moment out of step, keep the content pinned to the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        let hostingView = NSHostingView(rootView: AnyView(root))
        // No Auto Layout constraints, so AppKit never resizes the window on its own.
        hostingView.sizingOptions = []
        container.setContent(hostingView)
        self.hostingView = hostingView
        panel.setFrame(frame(forHeight: 600), display: false)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            close()
        } else if Date.now.timeIntervalSince(lastClosed) > 0.3 {
            // Clicking the item while the panel is open closes it on mouse-down; don't reopen it on mouse-up.
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        anchor = button
        // The content is only built while the panel is open; build it now so its height is known.
        onVisibilityChange?(true)
        container.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
        apply(frame(forHeight: contentHeight > 0 ? contentHeight : 600))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        button.highlight(true)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastClosed = .now
        anchor?.highlight(false)
        onVisibilityChange?(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard panel.isVisible, !isResizePending else { return }
        // This arrives in the middle of a layout pass. Resizing the window there makes AppKit apply
        // the change twice, overflowing the window, so wait until the pass has finished.
        isResizePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isResizePending = false
            if panel.isVisible {
                apply(frame(forHeight: contentHeight), animated: true)
            }
        }
    }

    /// Animated resizes glide with the content as Details or other sections open and close.
    private func apply(_ frame: NSRect, animated: Bool = false) {
        guard frame != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            container.layoutSubtreeIfNeeded()
        }
    }

    /// Hangs the glass just under the menu bar item, kept on screen. The window extends past the glass
    /// on the sides and bottom to leave room for its shadow.
    private func frame(forHeight height: CGFloat) -> NSRect {
        let margins = PanelContainerView.shadowMargins
        guard let itemWindow = anchor?.window, let screen = itemWindow.screen ?? NSScreen.main else {
            return NSRect(origin: panel.frame.origin,
                          size: NSSize(width: Self.width + margins.left + margins.right, height: ceil(height) + margins.bottom))
        }
        let item = itemWindow.frame
        let visible = screen.visibleFrame
        let glassTop = item.minY - 5
        // Never taller than the screen; the content scrolls instead.
        let glassSize = NSSize(width: Self.width, height: min(ceil(height), glassTop - visible.minY - 8))
        let glassX = min(max(item.minX, visible.minX + 8), visible.maxX - glassSize.width - 8)
        return NSRect(x: glassX - margins.left, y: glassTop - glassSize.height - margins.bottom,
                      width: glassSize.width + margins.left + margins.right, height: glassSize.height + margins.bottom)
    }
}

/// The panel's content: the glass, the SwiftUI content laid over it, and a soft shadow drawn only
/// outside the glass's rounded shape.
///
/// Everything here is laid out by hand. Content placed inside NSGlassEffectView gets Auto Layout
/// constraints, and AppKit then resized the window a second time on every change. And the window's
/// own shadow traces the whole window rectangle, leaving a dark outline around the rounded corners,
/// so the window has none and this view draws one instead.
final class PanelContainerView: NSView {
    static let shadowMargins = NSEdgeInsets(top: 0, left: 24, bottom: 32, right: 24)
    static let cornerRadius: CGFloat = 24

    let glass = NSGlassEffectView()
    var onClickOutsideGlass: (() -> Void)?
    private var content: NSView?

    private let shadowHost = NSView()
    private let shadowLayer = CALayer()
    private let shadowMask = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // A layer-hosting view, so AppKit leaves the shadow settings alone.
        shadowHost.layer = CALayer()
        shadowHost.wantsLayer = true
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.28
        shadowLayer.shadowRadius = 14
        shadowLayer.shadowOffset = CGSize(width: 0, height: -6)
        shadowMask.fillRule = .evenOdd
        shadowLayer.mask = shadowMask
        shadowHost.layer?.addSublayer(shadowLayer)
        addSubview(shadowHost)

        glass.cornerRadius = Self.cornerRadius
        addSubview(glass)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setContent(_ view: NSView) {
        content?.removeFromSuperview()
        addSubview(view, positioned: .above, relativeTo: glass)
        content = view
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    var glassFrame: NSRect {
        let margins = Self.shadowMargins
        return NSRect(x: margins.left, y: margins.bottom,
                      width: max(0, bounds.width - margins.left - margins.right),
                      height: max(0, bounds.height - margins.top - margins.bottom))
    }

    override func layout() {
        super.layout()
        glass.frame = glassFrame
        content?.frame = glassFrame
        shadowHost.frame = bounds

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let shape = CGPath(roundedRect: glassFrame, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius, transform: nil)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = shape
        // Everything except the glass, so the shadow never darkens the glass itself.
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(shape)
        shadowMask.frame = bounds
        shadowMask.path = outside
        CATransaction.commit()
    }

    /// A click on the shadow counts as a click outside the panel.
    override func mouseDown(with event: NSEvent) {
        if !glassFrame.contains(convert(event.locationInWindow, from: nil)) {
            onClickOutsideGlass?()
        }
    }
}

/// A borderless panel that can take keyboard focus without activating the app.
final class StatusPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        // PanelContainerView draws a shadow that follows the rounded glass.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
