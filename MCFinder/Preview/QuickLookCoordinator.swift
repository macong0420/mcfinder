import Quartz
import QuickLookUI

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var previewItems: [QLPreviewItem] = []
    private(set) var previewURLs: [URL] = []

    var acceptsPreviewPanelControl: Bool = true

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        acceptsPreviewPanelControl
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index < previewItems.count else { return nil }
        return previewItems[index]
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        false
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> CGRect {
        .zero
    }

    // MARK: - Public API

    func setPreviewItems(urls: [URL]) {
        previewURLs = urls
        previewItems = urls.map { $0 as NSURL }
        QLPreviewPanel.shared()?.reloadData()
    }

    func setSinglePreviewItem(url: URL) {
        setPreviewItems(urls: [url])
    }

    /// Always show the preview panel for the given URLs.
    /// Used by single-click to avoid the confusing toggle-on-same-row behavior.
    func showPreview(for urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }
        setPreviewItems(urls: urls)
        // Explicitly wire delegate/dataSource — in SwiftUI the coordinator
        // is not in the window's responder chain, so the standard
        // beginPreviewPanelControl callback is never invoked.
        panel.delegate = self
        panel.dataSource = self
        panel.makeKeyAndOrderFront(nil)
    }

    /// Toggle the preview panel visibility.
    /// Used by keyboard shortcut (space bar) where toggle semantics are expected.
    func togglePreview(for urls: [URL]) {
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPreview(for: urls)
        }
    }

    func closePreview() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }
}
