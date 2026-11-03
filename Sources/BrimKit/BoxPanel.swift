import AppKit

/// 点收纳格弹出来的那块面板。用 brim 自己画的玻璃面板，不用系统菜单：
/// 系统菜单里不能再弹一层菜单，收纳格就做不到“开着不收，点一个图标、它的菜单直接从图标下面接着弹出来”。
/// 样子照系统菜单：玻璃、圆角、阴影，挂在收纳格图标正下方。点面板外面、按 Esc、再点一次收纳格都会收起。
@MainActor
final class BoxPanel {
    /// 开着的那块面板。强引用：面板开着时就靠它管大小、管收起，收起时放掉
    private(set) static var current: BoxPanel?

    private let panel: KeyPanel
    private let stack = FlippedView()
    private let content: [NSView]
    private weak var button: NSStatusBarButton?
    private var monitors: [Any] = []
    private var frameObservers: [NSObjectProtocol] = []
    var onClose: (() -> Void)?
    private var laying = false

    static let padding: CGFloat = 6
    static let corner: CGFloat = 12

    /// content：从上到下几块（图标格、分隔线、扩展……），各自定好宽高
    init(content: [NSView], under button: NSStatusBarButton) {
        self.content = content
        self.button = button
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        content.forEach(stack.addSubview)

        let glass: NSView
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView()
            g.cornerRadius = Self.corner
            g.contentView = stack
            // 外面再套一层圆角裁切：里面有文字标签时，玻璃会在整个方块上铺一层很淡的底色，
            // 窗口阴影按它算，下面两个角就露出方角
            let clip = NSView()
            clip.wantsLayer = true
            clip.layer?.cornerRadius = Self.corner
            clip.layer?.masksToBounds = true
            g.autoresizingMask = [.width, .height]
            clip.addSubview(g)
            glass = clip
        } else {
            let v = NSVisualEffectView()
            v.material = .menu
            v.state = .active
            v.wantsLayer = true
            v.layer?.cornerRadius = Self.corner
            v.layer?.masksToBounds = true
            v.addSubview(stack)
            glass = v
        }
        panel.contentView = glass
        // 里面哪一块变高变矮（比如多了一行），面板跟着变
        for v in content {
            v.postsFrameChangedNotifications = true
            frameObservers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: v, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            })
        }
    }

    func show() {
        BoxPanel.current?.close()
        BoxPanel.current = self
        layout()
        button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
        // 打开时不选中任何输入框（不然第一个输入框里的字会被整段选中）
        panel.makeFirstResponder(nil)
        // 点面板外面就收起。brim 不在前台时，点在面板自己身上也会被当成“别的应用里的点击”，所以按位置判断；
        // 点在收纳格图标上也不算（那一下由收纳格自己处理：再点一次就收起）
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.contains(NSEvent.mouseLocation) else { return }
                self.close()
            }
        }) { monitors.append(m) }
        // brim 自己的窗口里点了面板外面、或者按了 Esc，也收起
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
                return event
            }
            if event.window !== self.panel, !self.contains(NSEvent.mouseLocation) { self.close() }
            return event
        }) { monitors.append(m) }
    }

    /// 屏幕上这个点在面板里，或者在收纳格图标上
    private func contains(_ p: NSPoint) -> Bool {
        if panel.frame.contains(p) { return true }
        if let button, let win = button.window {
            return win.convertToScreen(button.convert(button.bounds, to: nil)).insetBy(dx: -2, dy: -2).contains(p)
        }
        return false
    }

    /// fade：很快淡出（点中的那一格接着变成胶囊时用，不然面板一下子没了）
    func close(fade: Bool = false) {
        guard BoxPanel.current === self else { return }
        BoxPanel.current = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        frameObservers.forEach(NotificationCenter.default.removeObserver)
        frameObservers = []
        button?.highlight(false)
        if fade {
            let panel = panel
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; panel.animator().alphaValue = 0 }, completionHandler: { panel.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
        onClose?()
    }

    /// 从上到下排好，面板大小跟着内容，左上角挂在收纳格图标的左下角
    private func layout() {
        // 下面挪子视图的位置也会发“大小变了”的通知，再调回这里：不管它，不然打开一次要排好几遍
        guard !laying else { return }
        laying = true
        defer { laying = false }
        let width = (content.map(\.frame.width).max() ?? 200) + Self.padding * 2
        var y = Self.padding
        for v in content {
            v.setFrameOrigin(NSPoint(x: Self.padding, y: y))
            y += v.frame.height
        }
        let size = NSSize(width: width, height: y + Self.padding)
        stack.frame = NSRect(origin: .zero, size: size)
        var origin = NSPoint.zero
        if let button, let win = button.window {
            let r = win.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: r.minX, y: r.minY - 5 - size.height)
            // 别超出屏幕右边
            if let screen = win.screen ?? NSScreen.main, origin.x + size.width > screen.visibleFrame.maxX - 6 {
                origin.x = screen.visibleFrame.maxX - 6 - size.width
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// 面板不激活 brim 也能成为键盘焦点（里面的输入框能直接打字）
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 从上往下排的容器
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 面板里的一条细分隔线，和系统菜单的一样
final class PanelSeparator: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 11))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 14, y: 5, width: bounds.width - 28, height: 1).fill()
    }
}

/// 面板里一行可以点的字（“收纳格是空的，点击这里整理…”这类）
final class PanelLink: NSButton {
    private var handler: () -> Void = {}

    convenience init(title: String, width: CGFloat, action: @escaping () -> Void) {
        self.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        self.title = title
        isBordered = false
        alignment = .left
        font = .systemFont(ofSize: 13)
        contentTintColor = .labelColor
        handler = action
        target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { handler() }
}
