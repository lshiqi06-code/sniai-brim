import AppKit
import BrimCore
import ApplicationServices
import Observation
import SwiftUI

/// brim 要用户在系统设置里打开的权限。开关只能用户自己拨，brim 只负责把那一页打开、把 brim 递到手边。
/// 隐藏图标用的“菜单栏显示限制”不需要权限。
enum PermissionKind: String {
    /// 读菜单栏上的图标、替用户点它们（收纳必需）
    case accessibility
    /// 截菜单栏上图标本来的样子（可选）
    case screenRecording

    var title: String {
        switch self {
        case .accessibility: L("允许 brim 读取菜单栏图标", "Let brim read menu bar icons")
        case .screenRecording: L("允许 brim 显示图标在菜单栏上的样子", "Let brim show how icons look in the menu bar")
        }
    }

    var reason: String {
        switch self {
        case .accessibility: accessibilityReason
        case .screenRecording: L("收纳格里默认显示应用图标。打开“屏幕录制”后，brim 会在图标出现在菜单栏上时截下菜单栏那一小条，换成它本来的样子。截图只存在这台电脑上。打开后系统会让 brim 退出重开。", "Boxes show app icons by default. With Screen Recording on, brim captures the thin menu bar strip while an icon is showing and uses how it really looks. Captures stay on this Mac. The system will ask brim to quit and reopen.")
        }
    }

    private var accessibilityReason: String { L("brim 通过“辅助功能”读取菜单栏上有哪些图标，并在你点击收纳格里的图标时替你打开它的菜单。", "brim uses Accessibility to see which icons are in the menu bar, and to open an icon's menu when you click it in a box.") }

    /// 第一步怎么说。side 是设置窗口在引导窗的哪边（“左边”“右边”“旁边”）
    func dragStep(_ side: String) -> String { L("如果列表里没有 brim，把下面的 brim 拖进\(side)的列表", "If brim isn't in the list, drag brim below into the list on the \(side)") }

    var settingsURL: URL {
        switch self {
        case .accessibility: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture")!
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }
}

/// 权限引导：一键打开系统设置里那一页，在设置窗口旁边浮一个小窗，里面的 brim 图标直接拖进列表就行。
/// 用户打开开关后自动发现、自动收起，接着做原来要做的事。
@MainActor
final class PermissionGuide {
    private static var current: PermissionGuide?
    /// 有的权限打开后，系统会让 brim 退出重开；记下来，重开后告诉用户已经好了
    private static let pendingKey = "guide.pending"

    private let kind: PermissionKind
    private let onGranted: () -> Void
    private let model = GuideModel()
    private let panel: NSPanel
    private var poll: Timer?

    static func show(_ kind: PermissionKind, onGranted: @escaping () -> Void = {}) {
        if kind.isGranted { return onGranted() }
        current?.close()
        let guide = PermissionGuide(kind: kind, onGranted: onGranted)
        current = guide
        UserDefaults.standard.set(kind.rawValue, forKey: pendingKey)
        guide.start()
    }

    /// 启动时调用：上次引导到一半 brim 被系统重开了，权限已经有了就说一声
    static func resumeIfPending() {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        guard let kind = PermissionKind(rawValue: raw), kind.isGranted else { return }
        let guide = PermissionGuide(kind: kind, onGranted: {})
        current = guide
        guide.model.granted = true
        guide.panel.center()
        guide.panel.orderFrontRegardless()
        guide.finishSoon()
    }

    private init(kind: PermissionKind, onGranted: @escaping () -> Void) {
        self.kind = kind
        self.onGranted = onGranted
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 360),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.title = "brim"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false // 用户去点系统设置时 brim 会失去焦点，引导窗得留着
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let view = GuideView(kind: kind, model: model,
                             reopen: { [weak self] in self?.openSettings() },
                             cancel: { [weak self] in self?.cancel() })
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(panel.contentView!.fittingSize)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func start() {
        openSettings()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.granted, self.kind.isGranted else { return }
                self.model.granted = true
                self.finishSoon()
            }
        }
    }

    /// 打开设置那一页，等它的窗口出来，把引导窗贴在旁边
    private func openSettings() {
        NSWorkspace.shared.open(kind.settingsURL)
        Task { @MainActor in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(250))
                if let frame = Self.settingsWindowFrame() { return place(beside: frame) }
            }
            if !panel.isVisible { panel.center(); panel.orderFrontRegardless() }
        }
    }

    private func place(beside s: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(s) } ?? NSScreen.main
        let v = screen?.visibleFrame ?? s
        let size = panel.frame.size
        let gap: CGFloat = 14
        var x: CGFloat
        if s.maxX + gap + size.width <= v.maxX {
            x = s.maxX + gap
            model.side = .trailing // 设置窗口在左边
        } else if s.minX - gap - size.width >= v.minX {
            x = s.minX - gap - size.width
            model.side = .leading
        } else {
            // 两边都放不下：压在设置窗口左下角（侧边栏那块），不挡右边的列表
            x = s.minX + gap
            model.side = .overlap
        }
        x = min(max(x, v.minX), v.maxX - size.width)
        let y = min(max(s.maxY - size.height, v.minY), v.maxY - size.height)
        let target = NSRect(origin: NSPoint(x: x, y: model.side == .overlap ? max(s.minY + gap, v.minY) : y), size: size)
        if panel.isVisible {
            panel.animator().setFrame(target, display: true)
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
        }
    }

    /// 系统设置的主窗口在屏幕上的位置（换成 AppKit 的坐标：原点在左下）
    private static func settingsWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: b), r.width > 300, r.height > 200 else { continue }
            return NSRect(x: r.minX, y: top - r.maxY, width: r.width, height: r.height)
        }
        return nil
    }

    private func finishSoon() {
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        poll?.invalidate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            close()
            onGranted()
        }
    }

    private func cancel() {
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        close()
    }

    private func close() {
        stop()
        panel.close()
    }

    private func stop() {
        poll?.invalidate()
        poll = nil
        if Self.current === self { Self.current = nil }
    }
}

@MainActor @Observable
final class GuideModel {
    enum Side { case leading, trailing, overlap }
    var side: Side = .trailing
    var granted = false
}

private struct GuideView: View {
    let kind: PermissionKind
    let model: GuideModel
    let reopen: () -> Void
    let cancel: () -> Void

    private var sideWord: String {
        switch model.side {
        case .trailing: L("左侧", "left")
        case .leading, .overlap: L("右侧", "right")
        }
    }

    private var arrow: String { model.side == .trailing ? "arrow.left" : "arrow.right" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title).font(.headline)
            Text(kind.reason).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                step(1, kind.dragStep(sideWord))
                step(2, L("打开 brim 旁边的开关（系统可能会要求输入密码或使用触控 ID）", "Turn on the switch next to brim (you may need your password or Touch ID)"))
            }

            HStack(spacing: 12) {
                if model.side != .trailing { Spacer() }
                if model.side == .trailing { Image(systemName: arrow).font(.title2).foregroundStyle(.tertiary) }
                AppDragTileView().frame(width: 112, height: 104)
                if model.side != .trailing { Image(systemName: arrow).font(.title2).foregroundStyle(.tertiary) }
                if model.side == .trailing { Spacer() }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                if model.granted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(L("完成，brim 已获得权限", "Done. brim has permission"))
                } else {
                    ProgressView().controlSize(.small)
                    Text(L("等待你打开开关…", "Waiting for you to turn it on…")).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.callout)

            HStack {
                Button(L("重新打开设置", "Open Settings again"), action: reopen).buttonStyle(.link)
                Spacer()
                Button(L("以后再说", "Not now"), action: cancel).controlSize(.small)
            }
            .opacity(model.granted ? 0 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .frame(width: 340)
        .animation(.default, value: model.granted)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.weight(.semibold)).monospacedDigit()
                .frame(width: 18, height: 18)
                .background(Circle().fill(.quaternary))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AppDragTileView: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragTile { AppDragTile() }
    func updateNSView(_ view: AppDragTile, context: Context) {}
}

/// 能拖的 brim：拖出去的就是 brim.app 本身，和从访达里拖一样，系统设置的列表认得。
final class AppDragTile: NSView, NSDraggingSource {
    private let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    private var hovering = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    private var iconRect: NSRect {
        NSRect(x: bounds.midX - 28, y: bounds.maxY - 14 - 56, width: 56, height: 56)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        NSColor.labelColor.withAlphaComponent(hovering ? 0.08 : 0.04).setFill()
        box.fill()
        box.setLineDash([5, 4], count: 2, phase: 0)
        box.lineWidth = 1.2
        NSColor.labelColor.withAlphaComponent(0.25).setStroke()
        box.stroke()
        icon.draw(in: iconRect)
        let name = "brim" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = name.size(withAttributes: attrs)
        name.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: 12), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(iconRect, contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}
