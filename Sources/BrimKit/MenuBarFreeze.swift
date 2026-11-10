import AppKit
import ScreenCaptureKit

/// 把菜单栏“冻住”：拍一张菜单栏的照片盖在它上面。
/// 收纳格里的图标只能让它真的回到菜单栏、真的点一下才打得开时（读不到它的菜单、在后台按它也没反应），
/// 就在照片底下做这件事：图标出现、被点开、用完收回，你看到的菜单栏一直不动，只有它的菜单照常弹出来。
/// 照片窗口不拦鼠标，层级比菜单栏高、比应用弹出的菜单低。拍照要“屏幕录制”权限；没开就不冻，照旧会闪一下。
@MainActor
final class MenuBarFreeze {
    static let shared = MenuBarFreeze()

    private var panel: NSPanel?
    private var thawWork: DispatchWorkItem?
    /// 整屏的幕帘：比应用的菜单还高一层。要把“点了才生成”的菜单在底下真点开、读出来再关掉时用，那一下你看不到
    private var curtain: NSPanel?
    private var curtainWork: DispatchWorkItem?

    var isCurtained: Bool { curtain?.isVisible == true }

    var isFrozen: Bool { panel?.isVisible == true }

    /// 拍下菜单栏、盖上去，再往下做；拍不了就直接往下做
    func freeze(then next: @escaping () -> Void) {
        thawWork?.cancel()
        if isFrozen { return next() }
        guard IconCapture.allowed, #available(macOS 15.2, *), let screen = NSScreen.screens.first else { return next() }
        let height = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
        // 截图用“左上角为原点”的全局坐标，主屏幕的菜单栏就是最上面那一条
        let strip = CGRect(x: 0, y: 0, width: screen.frame.width, height: height)
        Task { @MainActor in
            guard let shot = try? await SCScreenshotManager.captureImage(in: strip) else { return next() }
            let p = self.panel ?? self.makePanel(level: Int(CGWindowLevelForKey(.statusWindow)) + 1)
            self.panel = p
            p.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height), display: false)
            (p.contentView as? NSImageView)?.image = NSImage(cgImage: shot, size: strip.size)
            p.orderFrontRegardless()
            // 等照片真的盖上去（下一帧）再动底下的菜单栏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { next() }
        }
    }

    /// 拍下整个屏幕（不带鼠标指针），菜单栏那一条照旧冻住，再整屏盖一张幕帘，然后往下做。
    /// 幕帘最多盖 2 秒，到时间自己揭开（不管中间出了什么岔子，屏幕都不会一直停着）。拍不了就返回 false，什么都不盖
    func freezeWholeScreen(then next: @escaping (Bool) -> Void) {
        thawWork?.cancel()
        guard IconCapture.allowed, let screen = NSScreen.screens.first else { return next(false) }
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return next(false) }
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = false
            guard let shot = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config) else { return next(false) }
            let barHeight = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY, 24)
            // 菜单栏那一条（幕帘揭开以后它还要再盖一会儿，等底下的图标收回去）
            if let strip = shot.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(shot.width), height: barHeight * scale)) {
                let p = self.panel ?? self.makePanel(level: Int(CGWindowLevelForKey(.statusWindow)) + 1)
                self.panel = p
                p.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - barHeight, width: screen.frame.width, height: barHeight), display: false)
                (p.contentView as? NSImageView)?.image = NSImage(cgImage: strip, size: NSSize(width: screen.frame.width, height: barHeight))
                p.orderFrontRegardless()
            }
            let c = self.curtain ?? self.makePanel(level: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)
            self.curtain = c
            c.setFrame(screen.frame, display: false)
            (c.contentView as? NSImageView)?.image = NSImage(cgImage: shot, size: screen.frame.size)
            c.orderFrontRegardless()
            self.curtainWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.liftCurtain() }
            self.curtainWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { next(true) }
        }
    }

    /// 揭开整屏的幕帘（菜单栏那一条不动，另外用 thaw 揭）
    func liftCurtain() {
        curtainWork?.cancel()
        curtainWork = nil
        curtain?.orderOut(nil)
        (curtain?.contentView as? NSImageView)?.image = nil
    }

    /// 底下的菜单栏收回原样以后再揭开照片（收回有一段动画）
    func thaw(after delay: TimeInterval = 1) {
        thawWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        thawWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 菜单栏图标在第 25 层，应用弹出的菜单在第 101 层：冻菜单栏的照片放在中间，整屏幕帘放在菜单上面
    private func makePanel(level: Int) -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = true
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.animationBehavior = .none // 系统默认的收窗动画会让底下的图标糊一下
        p.level = NSWindow.Level(rawValue: level)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        p.contentView = view
        return p
    }
}
