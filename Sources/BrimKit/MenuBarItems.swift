import AppKit
import BrimCore
import ApplicationServices

/// 菜单栏右边的一个图标（别的应用放的状态栏图标）。
struct MenuBarIcon: Identifiable, Equatable {
    /// “应用|#第几个”，换一次开机也认得出来，用来记住它放在哪个收纳格
    let id: String
    let appName: String
    let bundleID: String?
    let pid: pid_t
    /// 图标自己的说明，比如“Wi‑Fi”“电池”，有些应用不写
    let label: String
    let frame: CGRect
    let element: AXUIElement

    static func == (a: MenuBarIcon, b: MenuBarIcon) -> Bool { a.id == b.id && a.frame == b.frame }
}

/// 用“辅助功能”读出菜单栏上的所有图标。没有权限就什么也读不到。
enum MenuBarItems {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统的授权提示（只在没有权限时弹）
    static func askForPermission() {
        // 就是 kAXTrustedCheckOptionPrompt 的值；直接引用那个全局变量在 Swift 6 下编译不过
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// 上一遍读的时候等满了超时的进程（比如 Clash Verge 的网页进程）：一分钟内读全部时不再问它。
    /// 不然每次点开收纳格都要白等 0.2 秒，面板晚出来
    @MainActor private static var stalled: [pid_t: Date] = [:]

    /// 读一遍。每个应用最多等 0.2 秒，卡住的应用直接跳过。
    /// only：只读这一个应用（要逐个问所有在跑的应用，整个读一遍要花时间；等某个图标时不用）
    @MainActor static func scan(only bundleID: String? = nil) -> [MenuBarIcon] {
        guard trusted else { return [] }
        var out: [MenuBarIcon] = []
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = bundleID.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } ?? NSWorkspace.shared.runningApplications
        if bundleID == nil { stalled = stalled.filter { Date().timeIntervalSince($0.value) < 60 } }
        for app in apps where app.processIdentifier != me {
            let pid = app.processIdentifier
            if bundleID == nil, stalled[pid] != nil { continue }
            let ax = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(ax, 0.2)
            let asked = Date()
            guard let bar: AXUIElement = attribute(ax, kAXExtrasMenuBarAttribute) else {
                if Date().timeIntervalSince(asked) > 0.15 { stalled[pid] = Date() }
                continue
            }
            guard let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { continue }
            let appName = app.localizedName ?? app.bundleIdentifier ?? "?"
            var seen: [String: Int] = [:]
            for item in items {
                let label = (attribute(item, kAXDescriptionAttribute) as String?)
                    ?? (attribute(item, kAXTitleAttribute) as String?) ?? ""
                // 认图标不看它的说明文字：有的应用会换说明的语言（Gemini 一会儿英文一会儿中文），就成了两个图标。
                // 只看是这个应用的第几个图标
                let base = app.bundleIdentifier ?? appName
                let n = seen[base, default: 0]
                seen[base] = n + 1
                out.append(MenuBarIcon(id: "\(base)|#\(n)", appName: appName, bundleID: app.bundleIdentifier,
                                       pid: app.processIdentifier, label: label, frame: frame(of: item), element: item))
            }
        }
        return out.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 替用户“点一下”这个图标，打开它自己的菜单。
    /// 不用辅助功能里的“按下”动作：Clash Verge 这类（Tauri、Electron 做的）应用不理它。改成在图标上真的点一下，再把鼠标放回原处。
    /// right：右键（有的应用右键是另一份菜单）
    /// 点的时候先把光标藏起来，点完马上放回原处再显示：你看不到它跳到那个图标上又跳回来
    static func press(_ icon: MenuBarIcon, right: Bool = false) {
        let src = CGEventSource(stateID: .hidSystemState)
        let old = CGEvent(source: nil)?.location ?? .zero
        let p = CGPoint(x: icon.frame.midX, y: icon.frame.midY)
        let types: [CGEventType] = right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        CGDisplayHideCursor(CGMainDisplayID())
        for type in types {
            CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: right ? .right : .left)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        CGWarpMouseCursorPosition(old)
        CGDisplayShowCursor(CGMainDisplayID())
    }

    static func frame(of e: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let v: AXValue = attribute(e, kAXPositionAttribute) { AXValueGetValue(v, .cgPoint, &origin) }
        if let v: AXValue = attribute(e, kAXSizeAttribute) { AXValueGetValue(v, .cgSize, &size) }
        return CGRect(origin: origin, size: size)
    }

    static func attribute<T>(_ e: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
