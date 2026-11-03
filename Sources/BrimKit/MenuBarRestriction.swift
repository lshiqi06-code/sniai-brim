import AppKit
import BrimCore

/// macOS 27 的“菜单栏显示限制”：给系统一份“允许显示”的名单，名单外的图标由系统自己藏起来、重新排好。
/// 这是考试锁定模式用的私有框架 MenuBarClientCore。Hidden Bar（MIT）、Thaw、Ellipsis 在 macOS 27 上都是这么藏的；
/// 这里只借用这个思路，代码自己写。
///
/// 好处：马上生效，不改任何文件，不重启任何进程；brim 停止或退出（包括崩溃）时，系统自动把菜单栏还原。
/// 代价：只能按应用藏；私有接口，以后的 macOS 可能改掉，所以全部在运行时查找，找不到就当“不可用”。
@MainActor
final class MenuBarRestriction {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationClass = "MBAssessmentModeConfiguration"
    private static let assertionClass = "MBAssessmentModeAssertion"
    private static let initSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// 系统自己的图标（时钟、控制中心、Wi‑Fi 这些）用编号表示；不认识的编号系统会忽略，所以全放行。
    static let allSystemItems: [Int] = Array(0...63)

    private var assertion: NSObject?

    static var isAvailable: Bool {
        guard dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil,
              let config = NSClassFromString(configurationClass) as? NSObject.Type,
              let assertion = NSClassFromString(assertionClass) as? NSObject.Type else { return false }
        return config.instancesRespond(to: initSelector)
            && assertion.instancesRespond(to: activateSelector)
            && assertion.instancesRespond(to: invalidateSelector)
    }

    var isActive: Bool { assertion != nil }

    /// 只让这些应用的图标留在菜单栏上。新的限制生效以后才撤掉旧的，中间不会闪。
    func apply(allowing bundleIDs: [String], systemItems: [Int] = MenuBarRestriction.allSystemItems,
               completion: @escaping (Error?) -> Void) {
        guard Self.isAvailable,
              let configType = NSClassFromString(Self.configurationClass) as? NSObject.Type,
              let assertionType = NSClassFromString(Self.assertionClass) as? NSObject.Type else {
            return completion(Self.error(L("这台 Mac 不支持菜单栏显示限制（需要 macOS 27，或系统已更改）", "This Mac doesn't support the menu bar visibility restriction (needs macOS 27, or the system has changed)")))
        }
        // 两份名单都要是数组：框架按下标取，传集合会出错
        typealias Init = @convention(c) (AnyObject, Selector, NSArray, NSArray) -> NSObject?
        let blank = configType.perform(NSSelectorFromString("alloc")).takeUnretainedValue()
        let initImp = unsafeBitCast(configType.instanceMethod(for: Self.initSelector), to: Init.self)
        guard let config = initImp(blank, Self.initSelector, systemItems.map(NSNumber.init) as NSArray, bundleIDs as NSArray) else {
            return completion(Self.error(L("无法创建允许名单", "Couldn't create the allow list")))
        }
        let next = assertionType.init()
        typealias Activate = @convention(c) (AnyObject, Selector, AnyObject, @escaping @convention(block) (NSError?) -> Void) -> Void
        let activate = unsafeBitCast(assertionType.instanceMethod(for: Self.activateSelector), to: Activate.self)
        activate(next, Self.activateSelector, config) { [weak self] error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if error == nil {
                        let old = self.assertion
                        self.assertion = next
                        old.map(Self.invalidate)
                    }
                    completion(error)
                }
            }
        }
    }

    /// 撤掉限制，菜单栏回到原样
    func clear() {
        assertion.map(Self.invalidate)
        assertion = nil
    }

    private static func invalidate(_ a: NSObject) {
        guard a.responds(to: invalidateSelector) else { return }
        _ = a.perform(invalidateSelector)
    }

    private static func error(_ text: String) -> NSError {
        NSError(domain: "brim.restriction", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
