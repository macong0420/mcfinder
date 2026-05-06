import AppKit
import SwiftUI

final class QuickSearchPanel: NSPanel {
    let quickSearchState = QuickSearchState()
    private var hostingView: NSHostingView<QuickSearchView>?
    var searchEngine: SearchEngine?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 70),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
    }

    override var canBecomeKey: Bool { true }

    func createContentView(onSelect: @escaping (SearchResultItem) -> Void) {
        guard let engine = searchEngine else { return }

        let view = QuickSearchView(
            state: quickSearchState,
            searchEngine: engine,
            onSelect: { item in
                self.hide()
                onSelect(item)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let host = NSHostingView(rootView: view)
        host.frame.size = NSSize(width: 600, height: 600)
        contentView = host
        hostingView = host
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 70

        var frame = NSRect(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.maxY - panelHeight - 60,
            width: panelWidth,
            height: panelHeight
        )
        // Account for results expansion
        frame.size.height = 400

        setFrame(frame, display: false)
        quickSearchState.reset()
        makeKeyAndOrderFront(nil)
    }

    func hide() {
        orderOut(nil)
        quickSearchState.reset()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    override func resignKey() {
        super.resignKey()
    }

    override func cancelOperation(_ sender: Any?) {
        hide()
    }
}
