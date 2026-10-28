import AppKit
import Carbon.HIToolbox
import Observation

enum Retention: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, month = 30, threeMonths = 90, year = 365, forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        case .threeMonths: "3 Months"
        case .year: "1 Year"
        case .forever: "Forever"
        }
    }

    var cutoff: Date? {
        rawValue == 0 ? nil : Calendar.current.date(byAdding: .day, value: -rawValue, to: Date())
    }
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(cmdKey | optionKey), display: "⌥⌘C")
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var pasteDirectly: Bool { didSet { defaults.set(pasteDirectly, forKey: "pasteDirectly") } }
    var retention: Retention { didSet { defaults.set(retention.rawValue, forKey: "retention") } }
    var maxItems: Int { didSet { defaults.set(maxItems, forKey: "maxItems") } }
    var ignoreConcealed: Bool { didSet { defaults.set(ignoreConcealed, forKey: "ignoreConcealed") } }
    var ignoredBundleIDs: [String] { didSet { defaults.set(ignoredBundleIDs, forKey: "ignoredBundleIDs") } }
    var isPaused: Bool { didSet { defaults.set(isPaused, forKey: "isPaused") } }
    var hotKey: HotKeyCombo {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) { defaults.set(data, forKey: "hotKey") }
        }
    }

    private init() {
        defaults.register(defaults: [
            "pasteDirectly": true,
            "retention": Retention.month.rawValue,
            "maxItems": 5000,
            "ignoreConcealed": true,
            "ignoredBundleIDs": [String](),
            "isPaused": false,
        ])
        pasteDirectly = defaults.bool(forKey: "pasteDirectly")
        retention = Retention(rawValue: defaults.integer(forKey: "retention")) ?? .month
        maxItems = defaults.integer(forKey: "maxItems")
        ignoreConcealed = defaults.bool(forKey: "ignoreConcealed")
        ignoredBundleIDs = defaults.stringArray(forKey: "ignoredBundleIDs") ?? []
        isPaused = defaults.bool(forKey: "isPaused")
        if let data = defaults.data(forKey: "hotKey"), let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .default
        }
    }
}
