import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        let appName = AppConfig.appName

        // App
        let app = submenu(main, appName)
        app.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        // Settings: appearance and saving behaviour, grouped in one submenu.
        let settings = NSMenu(title: "Settings")
        for m in AppearanceMode.allCases {
            let item = NSMenuItem(title: "\(m.title) Appearance", action: #selector(AppDelegate.setAppearanceMode(_:)), keyEquivalent: "")
            item.tag = m.rawValue
            settings.addItem(item)
        }
        settings.addItem(.separator())
        settings.addItem(withTitle: "Show Line Numbers", action: #selector(AppDelegate.toggleLineNumbers(_:)), keyEquivalent: "")
        settings.addItem(withTitle: "Save on Focus Loss", action: #selector(AppDelegate.toggleSaveOnFocusLoss(_:)), keyEquivalent: "")
        app.addItem(withTitle: "Settings", action: nil, keyEquivalent: "").submenu = settings
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        add(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(appName)", action: #selector(AppDelegate.quitRequested(_:)), keyEquivalent: "q")

        // File
        let file = submenu(main, "File")
        file.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")
        file.addItem(withTitle: "New Window", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // "Open Recent" is inserted by AppKit automatically (after "Open…") for document-based apps.
        file.addItem(.separator())
        file.addItem(withTitle: "Close Tab", action: #selector(DocumentWindowController.closeTab(_:)), keyEquivalent: "w")
        add(file, "Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift])
        file.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        add(file, "Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        file.addItem(withTitle: "Rename…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Move To…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        file.addItem(withTitle: "Revert To Saved", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        file.addItem(.separator())
        let export = NSMenu(title: "Export")
        for f in ExportFormat.allCases {
            add(export, f.title, EditorWindowController.exportSelector(f), f.shortcut?.key ?? "", f.shortcut?.mods ?? [])
        }
        file.addItem(withTitle: "Export", action: nil, keyEquivalent: "").submenu = export
        file.addItem(.separator())
        add(file, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        file.addItem(withTitle: "Print…", action: #selector(EditorWindowController.printPreview(_:)), keyEquivalent: "p")

        // Edit
        let edit = submenu(main, "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        add(edit, "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift])
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        add(edit, "Copy Markdown", #selector(EditorWindowController.copyMarkdownDocument(_:)), "c", [.command, .shift])
        add(edit, "Copy HTML", #selector(EditorWindowController.copyHTML(_:)), "c", [.command, .option])
        add(edit, "Copy Rich Text", #selector(EditorWindowController.copyRichText(_:)), "c", [.command, .option, .shift])
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        findItem(find, "Find…", "f", [.command], .showFindInterface)
        findItem(find, "Find and Replace…", "f", [.command, .option], .showReplaceInterface)
        findItem(find, "Find Next", "g", [.command], .nextMatch)
        findItem(find, "Find Previous", "g", [.command, .shift], .previousMatch)
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find

        // Format
        let format = submenu(main, "Format")
        for c in [FormatCommand.bold, .italic, .underline, .strikethrough, .inlineCode, .superscript, .subscript] {
            format.addItem(c.menuItem())
        }
        format.addItem(.separator())
        let convert = NSMenu(title: "Paragraph Style")
        for c in [FormatCommand.normalText, .heading1, .heading2, .heading3, .heading4, .heading5, .heading6] {
            convert.addItem(c.menuItem())
        }
        format.addItem(withTitle: "Paragraph Style", action: nil, keyEquivalent: "").submenu = convert
        format.addItem(.separator())
        for c in [FormatCommand.bulletList, .numberedList, .taskList, .blockquote, .codeBlock] { format.addItem(c.menuItem()) }
        format.addItem(.separator())
        for c in [FormatCommand.indent, .outdent] { format.addItem(c.menuItem()) }
        format.addItem(.separator())
        for c in [FormatCommand.link, .image, .table, .horizontalRule, .comment] { format.addItem(c.menuItem()) }
        format.addItem(.separator())
        for c in [FormatCommand.newParagraph, .clearFormatting] { format.addItem(c.menuItem()) }

        // View
        let view = submenu(main, "View")
        add(view, "Hide Editor", #selector(EditorWindowController.toggleEditorPane(_:)), "e", [.command, .control])
        add(view, "Hide Preview", #selector(EditorWindowController.togglePreviewPane(_:)), "p", [.command, .control])
        view.addItem(.separator())
        add(view, "Hide Toolbar", #selector(EditorWindowController.toggleFormatBar(_:)), "t", [.command, .option])
        view.addItem(.separator())
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])

        // Window
        let window = submenu(main, "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        // ⌃Tab / ⌃⇧Tab, ⇧⌘] / ⇧⌘[ and ⌘1…⌘9 are handled by AppDelegate's key monitor (layout-independent).
        add(window, "Show Previous Tab", #selector(DocumentWindowController.showPreviousDocumentTab(_:)), "\t", [.control, .shift])
        add(window, "Show Next Tab", #selector(DocumentWindowController.showNextDocumentTab(_:)), "\t", [.control])
        window.addItem(withTitle: "Move Tab to New Window", action: #selector(DocumentWindowController.moveTabToNewWindow(_:)), keyEquivalent: "")
        window.addItem(withTitle: "Merge All Windows", action: #selector(DocumentWindowController.mergeAllWindows(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        // Help
        let help = submenu(main, "Help")
        help.addItem(withTitle: "Markdown Guide", action: #selector(AppDelegate.openMarkdownGuide(_:)), keyEquivalent: "")
        NSApp.helpMenu = help

        return main
    }

    private static func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        menu.addItem(item)
        return item
    }

    private static func findItem(_ menu: NSMenu, _ title: String, _ key: String, _ mods: NSEvent.ModifierFlags, _ action: NSTextFinder.Action) {
        let item = add(menu, title, #selector(NSResponder.performTextFinderAction(_:)), key, mods)
        item.tag = action.rawValue
    }
}
