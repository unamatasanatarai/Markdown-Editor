import AppKit

/// Optional: save edited documents as soon as the app or a document window loses focus.
///
/// Only documents that already have a file are saved (untitled ones keep using normal autosave).
/// Saving uses NSDocument's in-place autosave, so it is silent: no panels, and it plays well with
/// Versions ("Revert To").
final class FocusAutosave {
    static let shared = FocusAutosave()
    private let key = "SaveOnFocusLoss"
    private var observers: [NSObjectProtocol] = []

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveAll()
        })
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, window.windowController is DocumentWindowController,
                  window.attachedSheet == nil else { return } // a sheet (e.g. save panel) taking focus isn't "leaving"
            self?.saveAll()
        })
    }

    /// Documents that would be saved right now.
    static func documentsToSave(_ documents: [NSDocument]) -> [NSDocument] {
        documents.filter { $0.fileURL != nil && $0.isDocumentEdited && !$0.isLocked }
    }

    private func saveAll() {
        guard isEnabled else { return }
        for doc in Self.documentsToSave(NSDocumentController.shared.documents) {
            doc.autosave(withImplicitCancellability: false) { error in
                if let error = error { NSLog("Save on focus loss failed for %@: %@", doc.displayName, error.localizedDescription) }
            }
        }
    }
}
