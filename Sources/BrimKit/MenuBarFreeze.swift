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
            let p = self.panel ?? self.makePanel()
            self.panel = p
            p.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height), display: false)
            (p.contentView as? NSImageView)?.image = NSImage(cgImage: shot, size: strip.size)
            p.orderFrontRegardless()
            // 等照片真的盖上去（下一帧）再动底下的菜单栏
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { next() }
        }
    }

    /// 底下的菜单栏收回原样以后再揭开照片（收回有一段动画）
    func thaw(after delay: TimeInterval = 1) {
        thawWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        thawWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = true
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.animationBehavior = .none // 系统默认的收窗动画会让底下的图标糊一下
        // 菜单栏图标在第 25 层，应用弹出的菜单在第 101 层：放在中间
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        p.contentView = view
        return p
    }
}
