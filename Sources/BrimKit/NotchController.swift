import AppKit
import Observation
import SwiftUI

enum PineSide: String { case left, right }

/// 刘海这一块的状态：展开没有、松在哪边、长到第几行。
@MainActor @Observable
final class NotchModel {
    var expanded = false
    var side: PineSide = PineSide(rawValue: UserDefaults.standard.string(forKey: "pineSide") ?? "") ?? .right {
        didSet { UserDefaults.standard.set(side.rawValue, forKey: "pineSide") }
    }
    /// 鼠标在刘海上停多久才展开，设置里能改
    var openDelay: Double = UserDefaults.standard.object(forKey: "notch.openDelay") as? Double ?? 0.3 {
        didSet { UserDefaults.standard.set(openDelay, forKey: "notch.openDelay") }
    }
    var notchSize = CGSize(width: 186, height: 32)
    /// 屏幕没有刘海（外接显示器）时，brim 自己画一小截黑条当刘海
    var hasNotch = true
    /// 刘海往旁边伸出去的那一截，0 到 1
    var slotProgress: CGFloat = 0
    /// 松从树根往上长了几行
    var grow = -1
    /// 展开后整块黑色的大小，用来判断鼠标在不在面板上
    var islandSize = CGSize.zero

    private var growTask: Task<Void, Never>?

    /// 刘海先往旁边伸出一截，松再一行一行往上长，前后大约 1.5 秒。
    func startGrow() {
        growTask?.cancel()
        slotProgress = 0
        grow = -1
        growTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.4)) { slotProgress = 1 }
            try? await Task.sleep(for: .milliseconds(420))
            for row in 0..<13 {
                if Task.isCancelled { return }
                grow = row
                try? await Task.sleep(for: .milliseconds(85))
            }
            grow = .max
        }
    }
}

/// 管刘海那个窗口：放在哪、鼠标进出、展开收起。
@MainActor
final class NotchController {
    let model = NotchModel()
    private var panel: NSPanel!
    private var notchRect = NSRect.zero
    private var poll: Timer?
    private var pollFast = false
    private var hoverSince: Date?
    private var leftSince: Date?

    /// 鼠标离开面板多久收起。太长会显得“甩不掉”。
    static let closeDelay = 0.35
    static let windowSize = NSSize(width: 560, height: 560)

    func show() {
        let p = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        let host = FirstClickHostingView(rootView: NotchView(model: model, onToggle: { [weak self] in self?.toggle() }))
        host.sizingOptions = []
        p.contentView = host
        panel = p
        place()
        p.orderFrontRegardless()
        model.startGrow()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        startPoll(fast: false)
        // 点面板外面任何地方，马上收起。只看“点了”，不看点了什么，不需要权限。
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.expanded, !self.hotRect.contains(NSEvent.mouseLocation) else { return }
                self.setExpanded(false)
            }
        }
    }

    /// 有刘海的屏幕优先；都没有就用主屏幕，自己画一截。
    private func place() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let top = screen.frame.maxY
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            let h = screen.safeAreaInsets.top
            notchRect = NSRect(x: screen.frame.minX + l.width, y: top - h, width: screen.frame.width - l.width - r.width, height: h)
            model.hasNotch = true
        } else {
            let h = max(24, top - screen.visibleFrame.maxY)
            notchRect = NSRect(x: screen.frame.midX - 80, y: top - h, width: 160, height: h)
            model.hasNotch = false
        }
        model.notchSize = notchRect.size
        let s = Self.windowSize
        panel.setFrame(NSRect(x: notchRect.midX - s.width / 2, y: top - s.height, width: s.width, height: s.height), display: true)
    }

    /// 鼠标现在落在哪块算“刘海上”
    private var hotRect: NSRect {
        if model.expanded {
            let s = model.islandSize
            return NSRect(x: notchRect.midX - s.width / 2, y: notchRect.maxY - s.height, width: s.width, height: s.height)
        }
        var r = notchRect
        let slot = Theme.slotWidth * model.slotProgress
        r.size.width += slot
        if model.side == .left { r.origin.x -= slot }
        return r.insetBy(dx: 0, dy: -4)
    }

    /// 看鼠标在哪：靠近顶部面板或展开着时每秒 30 次，远的时候每秒 8 次（一直 30 次的话，空闲时也一直唤醒 CPU）
    private func startPoll(fast: Bool) {
        poll?.invalidate()
        pollFast = fast
        poll = Timer.scheduledTimer(withTimeInterval: fast ? 1 / 30 : 1 / 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        poll?.tolerance = fast ? 0.005 : 0.03
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        // 离面板 160 点以内就切快：鼠标划过这一段的工夫，够发现它要过来了
        let near = model.expanded || hotRect.insetBy(dx: -160, dy: -160).contains(mouse)
        if near != pollFast { startPoll(fast: near) }
        let inHot = hotRect.contains(mouse)
        // 只在鼠标落在刘海或面板上时接管点击，别的地方点击照常穿过去
        if panel.ignoresMouseEvents == inHot { panel.ignoresMouseEvents = !inHot }
        let now = Date()
        if !model.expanded {
            leftSince = nil
            guard inHot else { hoverSince = nil; return }
            if let since = hoverSince {
                if now.timeIntervalSince(since) >= model.openDelay { setExpanded(true) }
            } else {
                hoverSince = now
            }
        } else {
            hoverSince = nil
            guard !inHot else { leftSince = nil; return }
            if let since = leftSince {
                if now.timeIntervalSince(since) >= Self.closeDelay { setExpanded(false) }
            } else {
                leftSince = now
            }
        }
    }

    func toggle() { setExpanded(!model.expanded) }

    private func setExpanded(_ open: Bool) {
        hoverSince = nil
        leftSince = nil
        guard model.expanded != open else { return }
        if open { Extensions.notch?.willExpand() }
        withAnimation(.easeInOut(duration: 0.4)) { model.expanded = open }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 不用先点一下窗口才能点里面的东西
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
