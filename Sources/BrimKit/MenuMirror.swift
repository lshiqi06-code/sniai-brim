import AppKit
import BrimCore

/// 收纳格里点一个隐藏着的图标：不让它回到菜单栏，而是把它挂着的菜单读出来（辅助功能，不用按它），
/// 由 brim 弹一份一样的系统菜单；选哪一项，就在后台按那个应用里的哪一项。菜单栏始终不动。
/// 大部分应用的菜单栏菜单平时就挂在图标上；点了才临时生成菜单 / 面板的读不到，返回 nil（交给“冻住菜单栏后真点”）。
@MainActor
enum MenuMirror {
    static func read(_ item: MenuBarIcon) -> NSMenu? {
        AXUIElementSetMessagingTimeout(item.element, 0.5)
        guard let axMenu = openMenu(of: item.element) else { return nil }
        let menu = build(axMenu)
        return menu.items.contains { !$0.isSeparatorItem } ? menu : nil
    }

    /// 把卡在看不见的菜单里的应用放出来：图标隐藏着时被按过，菜单打开了却没地方显示，应用会一直停在那里（别的界面也不响应）。
    /// 对每个菜单栏图标挂着的菜单发一次“取消”；本来就没打开的菜单不受影响。brim 启动时做一次。
    static func releaseStuckMenus() {
        for item in MenuBarItems.scan() where !(item.bundleID ?? "").hasPrefix("com.apple.") {
            AXUIElementSetMessagingTimeout(item.element, 0.3)
            if let menu = openMenu(of: item.element) {
                AXUIElementPerformAction(menu, "AXCancel" as CFString)
            }
        }
    }

    /// 图标上现在挂着的菜单（没有就是 nil）
    static func openMenu(of owner: AXUIElement) -> AXUIElement? {
        children(owner).first { role($0) == kAXMenuRole }
    }

    private static func build(_ axMenu: AXUIElement) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for el in children(axMenu) {
            let title = (MenuBarItems.attribute(el, kAXTitleAttribute) as String?) ?? ""
            let enabled = (MenuBarItems.attribute(el, kAXEnabledAttribute) as Bool?) ?? true
            let sub = children(el).first { role($0) == kAXMenuRole }
            // 没有字、点不了、也没有子菜单的就是分隔线
            if title.isEmpty && sub == nil {
                if !enabled, menu.items.last.map({ !$0.isSeparatorItem }) == true { menu.addItem(.separator()) }
                continue
            }
            let item = MirrorItem(title: title, element: el)
            item.isEnabled = enabled
            if let mark = MenuBarItems.attribute(el, "AXMenuItemMarkChar") as String?, !mark.isEmpty { item.state = .on }
            if let key = MenuBarItems.attribute(el, "AXMenuItemCmdChar") as String?, !key.isEmpty, key.count == 1 {
                item.keyEquivalent = key.lowercased()
                item.keyEquivalentModifierMask = modifiers((MenuBarItems.attribute(el, "AXMenuItemCmdModifiers") as Int?) ?? 0)
            }
            if let sub { item.submenu = build(sub) }
            menu.addItem(item)
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        return menu
    }

    /// 辅助功能里的快捷键修饰：0 是只有 ⌘；1 ⇧、2 ⌥、4 ⌃ 往上加；8 表示没有 ⌘
    private static func modifiers(_ m: Int) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = m & 8 == 0 ? [.command] : []
        if m & 1 != 0 { f.insert(.shift) }
        if m & 2 != 0 { f.insert(.option) }
        if m & 4 != 0 { f.insert(.control) }
        return f
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] { MenuBarItems.attribute(e, kAXChildrenAttribute) ?? [] }
    private static func role(_ e: AXUIElement) -> String? { MenuBarItems.attribute(e, kAXRoleAttribute) }
}

/// brim 菜单里的一项，对应那个应用菜单里的同一项：选它就在后台按那一项
final class MirrorItem: NSMenuItem {
    nonisolated(unsafe) private let element: AXUIElement

    init(title: String, element: AXUIElement) {
        self.element = element
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() {
        // 等 brim 自己的菜单收起来再按，有的项会弹窗口或者对话框
        perform(#selector(press), with: nil, afterDelay: 0)
    }

    @MainActor @objc private func press() {
        AXUIElementSetMessagingTimeout(element, 0.5)
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }
}
