import AppKit
import BrimCore

/// 收纳格里点一个隐藏着的图标：不让它回到菜单栏，而是把它挂着的菜单读出来（辅助功能，不用按它），
/// 由 brim 弹一份一样的系统菜单；选哪一项，就在后台按那个应用里的哪一项。菜单栏始终不动。
/// 大部分应用的菜单栏菜单平时就挂在图标上，直接读（read）。
/// 有的应用（Claude）点了才生成菜单，而且不挂在图标上、挂在应用下面：要在遮住的屏幕底下真点开一次，
/// 按位置找到它读出来（readOpened），马上关掉；关掉以后里面的项照样能按。弹出的是面板、窗口的读不到，返回 nil。
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

    /// 刚被点开的菜单：在图标正下方按位置找（它可能不挂在图标上），往上找到整份菜单。没开、或者开的不是菜单就是 nil
    static func openedMenu(of item: MenuBarIcon) -> AXUIElement? {
        if let attached = openMenu(of: item.element) { return attached }
        let app = AXUIElementCreateApplication(item.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(item.frame.midX), Float(item.frame.maxY + 14), &hit) == .success, var cur = hit else { return nil }
        for _ in 0..<8 {
            if role(cur) == kAXMenuRole { return cur }
            guard let up: AXUIElement = MenuBarItems.attribute(cur, kAXParentAttribute) else { return nil }
            cur = up
        }
        return nil
    }

    /// 把刚点开的菜单读成一份一样的（没有能选的项就是 nil），同时给回原菜单，用来关掉它
    static func readOpened(_ item: MenuBarIcon) -> (menu: NSMenu, source: AXUIElement)? {
        guard let axMenu = openedMenu(of: item) else { return nil }
        let menu = build(axMenu)
        return menu.items.contains { !$0.isSeparatorItem && $0.isEnabled && $0.view == nil } ? (menu, axMenu) : nil
    }

    static func cancel(_ axMenu: AXUIElement) {
        AXUIElementPerformAction(axMenu, kAXCancelAction as CFString)
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
            // 没有字、里面是应用自己画的一块（几行字、进度条）：照着画一行，只看不能点
            if title.isEmpty && sub == nil, let custom = customItem(el) {
                menu.addItem(custom)
                continue
            }
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

    /// 应用自己画的菜单项（比如用量：左边名字、右边数字、下面一条进度）。读出里面的字和进度，画成一样排法的一行；
    /// 只有一段字的当小标题。里面什么都读不到就是 nil
    private static func customItem(_ el: AXUIElement) -> NSMenuItem? {
        var texts: [String] = []
        var progress: Double?
        func walk(_ e: AXUIElement, _ depth: Int) {
            for c in children(e) {
                switch role(c) {
                case kAXStaticTextRole:
                    if let t: String = MenuBarItems.attribute(c, kAXValueAttribute), !t.isEmpty { texts.append(t) }
                case kAXProgressIndicatorRole, kAXLevelIndicatorRole:
                    if let v: Double = MenuBarItems.attribute(c, kAXValueAttribute) { progress = v }
                default:
                    if depth < 4 { walk(c, depth + 1) }
                }
            }
        }
        walk(el, 0)
        guard !texts.isEmpty else { return nil }
        if texts.count == 1, progress == nil { return .sectionHeader(title: texts[0]) }
        let item = NSMenuItem()
        item.view = MirrorInfoView(left: texts[0], right: texts.dropFirst().joined(separator: "  "), progress: progress)
        return item
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

/// 照着应用自己画的那一行画：左边名字，右边数字，下面一条进度
final class MirrorInfoView: NSView {
    private let left: String
    private let right: String
    private let progress: Double?

    init(left: String, right: String, progress: Double?) {
        self.left = left
        self.right = right
        self.progress = progress
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: progress == nil ? 24 : 44))
        autoresizingMask = [.width]
        setAccessibilityLabel([left, right].filter { !$0.isEmpty }.joined(separator: "，"))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 14
        let font = NSFont.menuFont(ofSize: 0)
        let l = NSAttributedString(string: left, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let r = NSAttributedString(string: right, attributes: [.font: NSFont.menuFont(ofSize: font.pointSize - 1), .foregroundColor: NSColor.secondaryLabelColor])
        l.draw(at: NSPoint(x: inset, y: 4))
        r.draw(at: NSPoint(x: bounds.width - inset - r.size().width, y: 5))
        guard let progress else { return }
        let track = NSRect(x: inset, y: 29, width: bounds.width - inset * 2, height: 6)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        var bar = track
        bar.size.width = max(6, track.width * min(1, max(0, progress)))
        // 快用完了用警示色，和系统的电量、储存空间一个习惯
        (progress >= 0.9 ? NSColor.systemRed : NSColor.controlAccentColor).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
    }
}
