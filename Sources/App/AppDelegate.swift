import Cocoa

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var keyMonitor: Any?

    /// `MarkdownEditor --export <input.md> <output.(html|pdf|odt|docx|rtf)>` converts headlessly and exits.
    private lazy var exportArgs: (URL, URL)? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--export"), i + 2 < args.count else { return nil }
        return (URL(fileURLWithPath: args[i + 1]), URL(fileURLWithPath: args[i + 2]))
    }()

    public func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSDocumentController.shared
        // Tabs live inside our own windows; macOS window tabbing would add a hidden NSWindow per tab.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build()
        AppearanceManager.shared.apply()
        installShortcutMonitor()
        FocusAutosave.shared.start()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if let (input, output) = exportArgs {
            runCommandLineExport(input, output)
        }
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if exportArgs != nil {
            // Command-line paths are export arguments, not documents to open.
            sender.reply(toOpenOrPrint: .success)
            return
        }
        for name in filenames {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: name), display: true) { _, _, error in
                if let error = error { NSApp.presentError(error) }
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        exportArgs == nil
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func toggleLineNumbers(_ sender: Any?) {
        LineNumberSettings.isEnabled.toggle()
    }

    @objc func toggleSaveOnFocusLoss(_ sender: Any?) {
        FocusAutosave.shared.isEnabled.toggle()
    }

    /// ⌘T: new untitled document as a tab in the front window.
    @objc func newTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    /// ⌘N: new untitled document in its own window.
    @objc func newWindow(_ sender: Any?) {
        DocumentWindowController.openNextInNewWindow = true
        defer { DocumentWindowController.openNextInNewWindow = false }
        NSDocumentController.shared.newDocument(sender)
    }

    /// Quit menu item / ⌘Q: needs a second press within 1.5 s (see QuitGuard).
    @objc func quitRequested(_ sender: Any?) {
        QuitGuard.shared.requestQuit()
    }

    @objc func setAppearanceMode(_ sender: NSMenuItem) {
        AppearanceManager.shared.mode = AppearanceMode(rawValue: sender.tag) ?? .system
    }

    @objc func openMarkdownGuide(_ sender: Any?) {
        if let url = URL(string: "https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax") {
            NSWorkspace.shared.open(url)
        }
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLineNumbers(_:)) {
            menuItem.state = LineNumberSettings.isEnabled ? .on : .off
        }
        if menuItem.action == #selector(toggleSaveOnFocusLoss(_:)) {
            menuItem.state = FocusAutosave.shared.isEnabled ? .on : .off
        }
        if menuItem.action == #selector(setAppearanceMode(_:)) {
            menuItem.state = menuItem.tag == AppearanceManager.shared.mode.rawValue ? .on : .off
        }
        return true
    }

    /// ⇧⌘7/8/9 produce layout-dependent characters (e.g. "&", "*", "("), so match them by key code.
    private func installShortcutMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if let host = NSApp.keyWindow?.windowController as? DocumentWindowController,
               Self.handleTabShortcut(event.keyCode, flags, host) {
                return nil
            }
            guard flags == [.command, .shift], let cmd = FormatCommand.shiftedDigitKeyCodes[event.keyCode] else {
                return event
            }
            let sender = NSMenuItem()
            sender.tag = cmd.rawValue
            if NSApp.sendAction(#selector(EditorWindowController.performFormat(_:)), to: nil, from: sender) {
                return nil
            }
            return event
        }
    }

    /// Tab navigation by key code: ⌃Tab / ⌃⇧Tab, ⇧⌘] / ⇧⌘[, ⌘1…⌘9 (⌘9 = last tab).
    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    private static func handleTabShortcut(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags, _ host: DocumentWindowController) -> Bool {
        switch (keyCode, flags) {
        case (48, [.control]), (30, [.command, .shift]):
            host.showNextDocumentTab(nil)
        case (48, [.control, .shift]), (33, [.command, .shift]):
            host.showPreviousDocumentTab(nil)
        case (_, [.command]) where digitKeyCodes[keyCode] != nil:
            host.selectTab(number: digitKeyCodes[keyCode]!)
        default:
            return false
        }
        return true
    }

    private func runCommandLineExport(_ input: URL, _ output: URL) {
        func fail(_ msg: String) -> Never {
            FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
            exit(1)
        }
        guard let format = ExportFormat.from(extension: output.pathExtension) else {
            fail("unsupported output type '\(output.pathExtension)' (use html, pdf, odt, docx or rtf)")
        }
        guard let data = try? Data(contentsOf: input) else { fail("cannot read \(input.path)") }
        let markdown = TextDecoding.decode(data).text
        let title = input.deletingPathExtension().lastPathComponent
        Exporter.export(markdown: markdown, title: title, baseURL: input.deletingLastPathComponent(),
                        format: format, to: output) { error in
            if let error = error { fail(error.localizedDescription) }
            print("Exported \(output.path)")
            exit(0)
        }
    }
}
