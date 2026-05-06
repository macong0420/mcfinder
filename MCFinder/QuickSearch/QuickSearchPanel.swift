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
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame

        let panelWidth: CGFloat = 600
        // Always allocate enough height for the expanded results list. The
        // SwiftUI content draws its rounded material only around the actual
        // VStack (search field + results), so unused panel space is invisible
        // and inert — see QuickSearchView.body.
        let panelHeight: CGFloat = 400

        // Spotlight-style placement: panel's TOP edge sits in the upper third
        // of the visible screen, horizontally centred.
        //
        // Cocoa origin is bottom-left, so we compute originY from the *top*:
        //   panelTopY (in screen coords) = screenFrame.maxY - topMargin
        //   originY                       = panelTopY - panelHeight
        // Previously the code mutated `frame.size.height` after setting `y`
        // assuming a 70pt panel, which let the panel grow upward off-screen
        // and forced macOS to clamp it flush against the menu bar.
        let topMargin = max(80, (screenFrame.height - panelHeight) / 4)
        let originY = screenFrame.maxY - panelHeight - topMargin

        let frame = NSRect(
            x: round(screenFrame.midX - panelWidth / 2),
            y: round(originY),
            width: panelWidth,
            height: panelHeight
        )

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
