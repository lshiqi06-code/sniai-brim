import Foundation
import Observation

/// 界面语言：跟随系统、中文、English。设置 › 通用里切，马上生效（界面上的字都写成 L("中文", "English")）。
/// 用语按 docs/用语.md。
@Observable
public final class Lang: @unchecked Sendable {
    public enum Choice: String, CaseIterable, Sendable { case system, zh, en }

    public static let shared = Lang()

    public var choice: Choice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "language") }
    }

    init() {
        choice = Choice(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
    }

    public var isEnglish: Bool {
        switch choice {
        case .zh: false
        case .en: true
        case .system: !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        }
    }
}

/// 一句界面上的字，中英各一份
public func L(_ zh: String, _ en: String) -> String {
    Lang.shared.isEnglish ? en : zh
}
