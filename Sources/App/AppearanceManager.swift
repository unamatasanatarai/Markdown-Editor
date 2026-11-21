import AppKit

enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: NSImage {
        switch self {
        case .system: return Icons.symbol("circle.lefthalf.filled", fallback: "A")
        case .light: return Icons.symbol("sun.max", fallback: "☀")
        case .dark: return Icons.symbol("moon", fallback: "☾")
        }
    }
}

/// App-wide light/dark mode: follows the system by default, can be forced to light or dark.
final class AppearanceManager {
    static let shared = AppearanceManager()
    static let didChange = Notification.Name("AppearanceManagerDidChange")
    private let key = "AppearanceMode"

    var mode: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            apply()
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
