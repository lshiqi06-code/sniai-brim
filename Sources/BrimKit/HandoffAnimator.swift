import AppKit
import BrimCore
import QuartzCore

/// 打开“菜单只能挂在自己图标上”的 app 时的动画，用户在设置里选
enum HandoffStyle: String, CaseIterable, Identifiable {
    /// 岛：点中的那一格变成一颗黑色胶囊（和顶部面板同一种黑），带着图标升到菜单栏
    case island
    /// 归位：图标从格子里浮起，沿一道弧线飞回它在菜单栏上的位置
    case flight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .island: L("岛", "Island")
        case .flight: L("归位", "Return")
        }
    }

    static var current: HandoffStyle {
        get { HandoffStyle(rawValue: UserDefaults.standard.string(forKey: "stash.handoff") ?? "") ?? .island }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "stash.handoff") }
    }
}

/// 把“从收纳格到它在菜单栏上的位置”这一段演出来。这类 app 的菜单只认自己图标的位置，brim 挪不动，
/// 只能在冻住的菜单栏底下让图标回到原位再点；这里在照片上面再盖一层透明的动画层，比应用弹出的菜单低一层：
/// 图标（或胶囊）落到原位以后就停在那里，盖住真图标，应用的菜单从它下面弹出；菜单关了再回到帽檐。
/// 所有坐标都是屏幕坐标（左下角为原点）。
@MainActor
final class HandoffAnimator {
    static let shared = HandoffAnimator()

    private var window: NSPanel?
    private var icon: CALayer?
    /// 归位：图标背后一小块“按下”的底；岛：黑色胶囊
    private var back: CALayer?
    private var style: HandoffStyle = .island
    private var box: NSRect = .zero
    private var landed: NSPoint?
    private var tint: NSColor = .white

    var isActive: Bool { window != nil }

    static let capsule = NSSize(width: 46, height: 26)
    /// 院子色的青绿（Theme.leaf）
    static let leaf = NSColor(red: 0.33, green: 0.70, blue: 0.60, alpha: 1)

    /// 开始：图标还在收纳格那一格里（cell），面板在 panel，帽檐在 box。
    /// guess 是它隐藏前在菜单栏上的位置：一开始就朝那里去，等系统量出准确位置（land）再顺一下，不在原地干等
    func begin(image: NSImage, tint: NSColor, cell: NSRect, panel: NSRect, box: NSRect, guess: NSRect?) {
        guard let screen = NSScreen.screens.first, let (iconLayer, backLayer) = prepare(image: image, tint: tint, box: box) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch style {
        case .flight:
            // 图标在格子里浮起来一点
            iconLayer.position = local(NSPoint(x: cell.midX, y: cell.midY))
            iconLayer.shadowOpacity = 0.45
            iconLayer.shadowRadius = 6
            iconLayer.shadowOffset = CGSize(width: 0, height: -3)
            backLayer.opacity = 0
            CATransaction.commit()
            animate(iconLayer, "transform.scale", from: 1, to: 1.18, duration: 0.18)
            if let guess { fly(iconLayer, to: local(NSPoint(x: guess.midX, y: guess.midY)), lift: 36, duration: 0.55, delay: 0.12) }
        case .island:
            // 点中的那一格变成一颗小黑胶囊（图标一直在它正中），从格子里升到菜单栏；面板同时淡出
            backLayer.backgroundColor = NSColor.black.cgColor
            backLayer.frame = local(cell)
            backLayer.cornerRadius = 9
            iconLayer.position = local(NSPoint(x: cell.midX, y: cell.midY))
            CATransaction.commit()
            animate(backLayer, "opacity", from: 0, to: 1, duration: 0.1)
            let barY = screen.frame.maxY - 2 - Self.capsule.height / 2
            let x = guess?.midX ?? box.midX
            let to = CGRect(x: x - Self.capsule.width / 2, y: barY - Self.capsule.height / 2,
                            width: Self.capsule.width, height: Self.capsule.height)
            morph(backLayer, to: local(to), radius: Self.capsule.height / 2, duration: 0.5)
            fly(iconLayer, to: local(NSPoint(x: to.midX, y: to.midY)), lift: 0, duration: 0.5, delay: 0)
        }
    }

    /// 建动画层：盖住屏幕顶上一截（够从收纳格飞到菜单栏），不拦鼠标
    private func prepare(image: NSImage, tint: NSColor, box: NSRect) -> (CALayer, CALayer)? {
        cancel()
        guard let screen = NSScreen.screens.first else { return nil }
        style = HandoffStyle.current
        self.box = box
        self.tint = tint
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - 260, width: screen.frame.width, height: 260)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.hidesOnDeactivate = false
        w.animationBehavior = .none
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1) // 和冻住的照片同层，排在它上面；比应用的菜单（101）低
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let root = view.layer!
        root.contentsScale = screen.backingScaleFactor
        w.contentView = view
        w.orderFrontRegardless()
        window = w

        let iconLayer = CALayer()
        iconLayer.contents = Self.tinted(image, tint: style == .island ? Self.leaf : tint)
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.contentsScale = screen.backingScaleFactor
        iconLayer.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        let backLayer = CALayer()
        root.addSublayer(backLayer)
        root.addSublayer(iconLayer)
        icon = iconLayer
        back = backLayer
        return (iconLayer, backLayer)
    }

    /// 吞进来：胶囊从帽檐出来，滑到菜单栏上的那个图标（target）上盖住它，这时才让系统隐藏真图标（hide），
    /// 然后带着图标滑回帽檐、化开。动画不需要冻住菜单栏：真图标消失时正好被胶囊盖着，旁边的图标由系统自己靠拢。
    func swallow(image: NSImage, tint: NSColor, target: NSRect, box: NSRect, hide: @escaping () -> Void, done: @escaping () -> Void = {}) {
        guard let (iconLayer, backLayer) = prepare(image: image, tint: tint, box: box) else { hide(); return done() }
        let center = local(NSPoint(x: target.midX, y: target.midY))
        let boxCenter = local(NSPoint(x: box.midX, y: box.midY))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.position = center
        if style == .island {
            iconLayer.opacity = 0
            backLayer.backgroundColor = NSColor.black.cgColor
            backLayer.frame = CGRect(x: boxCenter.x - 11, y: boxCenter.y - 11, width: 22, height: 22)
            backLayer.cornerRadius = 11
        } else {
            backLayer.opacity = 0
        }
        CATransaction.commit()
        switch style {
        case .island:
            let size = capsuleSize(for: target)
            morph(backLayer, to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                  radius: size.height / 2, duration: 0.34)
            after(0.34) { [weak self] in
                guard let self else { return }
                // 盖住了：图标在胶囊里亮起来，真图标消失
                self.animate(iconLayer, "opacity", from: 0, to: 1, duration: 0.1)
                hide()
                // 系统淡出真图标要一点时间，等它消失了胶囊再走，不留残影
                self.after(0.36) {
                    self.goHome(iconLayer, backLayer, duration: 0.4, done: done)
                }
            }
        case .flight:
            hide()
            fly(iconLayer, to: boxCenter, lift: 12, duration: 0.42, delay: 0)
            animate(iconLayer, "transform.scale", from: 1, to: 0.5, duration: 0.42)
            animate(iconLayer, "opacity", from: 1, to: 0, duration: 0.42)
            after(0.42) { [weak self] in
                self?.cancel()
                done()
            }
        }
    }

    /// 吐出来：胶囊带着图标从帽檐出来，滑到它在菜单栏上的位置（guess 是隐藏前的位置）；路上让系统把真图标显示出来（reveal），
    /// 到了以后读真实位置（actual）再顺一下，胶囊化开，真图标留在那里。
    func spit(image: NSImage, tint: NSColor, box: NSRect, guess: NSRect?, reveal: @escaping () -> Void,
              actual: @escaping () -> NSRect?, done: @escaping () -> Void = {}) {
        guard let (iconLayer, backLayer) = prepare(image: image, tint: tint, box: box) else { reveal(); return done() }
        let boxCenter = local(NSPoint(x: box.midX, y: box.midY))
        let first = guess.map { local(NSPoint(x: $0.midX, y: $0.midY)) } ?? CGPoint(x: boxCenter.x - 90, y: boxCenter.y)
        let size = guess.map(capsuleSize) ?? Self.capsule
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.position = boxCenter
        if style == .island {
            backLayer.backgroundColor = NSColor.black.cgColor
            backLayer.frame = CGRect(x: boxCenter.x - 11, y: boxCenter.y - 11, width: 22, height: 22)
            backLayer.cornerRadius = 11
        } else {
            backLayer.opacity = 0
        }
        CATransaction.commit()
        let duration = 0.42
        fly(iconLayer, to: first, lift: style == .island ? 0 : 12, duration: duration, delay: 0)
        if style == .island {
            morph(backLayer, to: CGRect(x: first.x - size.width / 2, y: first.y - size.height / 2, width: size.width, height: size.height),
                  radius: size.height / 2, duration: duration)
        }
        after(0.1, reveal)
        after(duration) { [weak self] in
            guard let self else { return }
            // 量真实位置，有偏差就再顺一下，然后化开，露出底下的真图标
            var settle = 0.0
            if let real = actual().map({ self.local(NSPoint(x: $0.midX, y: $0.midY)) }), hypot(real.x - first.x, real.y - first.y) > 4 {
                settle = 0.16
                self.fly(iconLayer, to: real, lift: 0, duration: settle, delay: 0)
                if self.style == .island {
                    self.morph(backLayer, to: CGRect(x: real.x - size.width / 2, y: real.y - size.height / 2, width: size.width, height: size.height),
                               radius: size.height / 2, duration: settle)
                }
            }
            self.after(settle + 0.08) {
                self.animate(iconLayer, "opacity", from: 1, to: 0, duration: 0.22)
                if self.style == .island { self.animate(backLayer, "opacity", from: 1, to: 0, duration: 0.22) }
                self.after(0.22) {
                    self.cancel()
                    done()
                }
            }
        }
    }

    /// 胶囊带着图标回到帽檐：一起滑过去、收小，快到时化开
    private func goHome(_ icon: CALayer, _ back: CALayer, duration: Double, done: @escaping () -> Void) {
        let boxCenter = local(NSPoint(x: box.midX, y: box.midY))
        fly(icon, to: boxCenter, lift: 0, duration: duration, delay: 0)
        animate(icon, "transform.scale", from: 1, to: 0.6, duration: duration)
        animate(icon, "opacity", from: 1, to: 0, duration: duration * 0.4, delay: duration * 0.6)
        morph(back, to: CGRect(x: boxCenter.x - 11, y: boxCenter.y - 11, width: 22, height: 22), radius: 11, duration: duration)
        animate(back, "opacity", from: 1, to: 0, duration: duration * 0.4, delay: duration * 0.6)
        after(duration) { [weak self] in
            self?.cancel()
            done()
        }
    }

    private func capsuleSize(for target: NSRect) -> NSSize {
        NSSize(width: max(Self.capsule.width, target.width + 8), height: Self.capsule.height)
    }

    private func after(_ seconds: Double, _ f: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            f()
        }
    }

    /// 落位：知道它在菜单栏上真正的位置了（target），飞过去 / 滑过去；快到的时候调用 then（去真的点它），
    /// 这样它的菜单差不多在落位那一刻弹出来
    func land(on target: NSRect, then: @escaping () -> Void) {
        guard let icon, let back, let screen = NSScreen.screens.first else { return then() }
        let center = NSPoint(x: target.midX, y: target.midY)
        landed = center
        // 一开始就朝它隐藏前的位置去了：准确位置差不多就只收个尾，差得远再挪过去
        let shown = (icon.presentation() ?? icon).position
        let near = style == .flight ? hypot(shown.x - local(center).x, shown.y - local(center).y) < 6
                                    : abs((back.presentation() ?? back).position.x - local(center).x) < 6
        let duration = near ? 0.2 : 0.32
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration * 0.5))
            then()
        }
        switch style {
        case .flight:
            let to = local(center)
            fly(icon, to: to, lift: near ? 0 : 18, duration: duration, delay: 0)
            animate(icon, "transform.scale", from: (icon.presentation() ?? icon).value(forKeyPath: "transform.scale") ?? 1.18, to: 1, duration: duration)
            animate(icon, "shadowOpacity", from: 0.45, to: 0, duration: duration)
            // 落下后背后亮起一小块“按下”的底，和点菜单栏图标时系统画的一样。
            // 不透明：照片里这个位置可能正好是别的图标（它回来以后别的图标会往左让，照片里没让）
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            back.frame = local(NSRect(x: target.midX - target.width / 2 - 3, y: screen.frame.maxY - 2 - 24, width: target.width + 6, height: 22))
            back.cornerRadius = 11
            let darkIcon = (tint.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1) < 0.5
            back.backgroundColor = NSColor(white: darkIcon ? 0.86 : 0.26, alpha: 1).cgColor
            CATransaction.commit()
            animate(back, "opacity", from: 0, to: 1, duration: 0.2, delay: duration * 0.8)
        case .island:
            let barY = screen.frame.maxY - 2 - Self.capsule.height / 2
            let to = CGRect(x: center.x - Self.capsule.width / 2, y: barY - Self.capsule.height / 2,
                            width: Self.capsule.width, height: Self.capsule.height)
            morph(back, to: local(to), radius: Self.capsule.height / 2, duration: duration)
            fly(icon, to: local(NSPoint(x: to.midX, y: to.midY)), lift: 0, duration: duration, delay: 0)
        }
    }

    /// 收回：菜单关了，回到帽檐，再收起动画层
    func finish(then: @escaping () -> Void) {
        guard let icon, let back else { cancel(); return then() }
        let duration = 0.36
        let boxCenter = local(NSPoint(x: box.midX, y: box.midY))
        switch style {
        case .flight:
            animate(back, "opacity", from: 1, to: 0, duration: 0.14)
            let from = icon.position
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: boxCenter, control: CGPoint(x: (from.x + boxCenter.x) / 2, y: from.y + 14))
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.duration = duration
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            icon.position = boxCenter
            icon.add(move, forKey: "back")
            animate(icon, "transform.scale", from: 1, to: 0.5, duration: duration)
            animate(icon, "opacity", from: 1, to: 0, duration: duration)
        case .island:
            // 吞回去：图标留在胶囊里一起滑回帽檐
            return goHome(icon, back, duration: 0.4, done: then)
        }
        after(duration) { [weak self] in
            self?.cancel()
            then()
        }
    }

    func cancel() {
        window?.orderOut(nil)
        window = nil
        icon = nil
        back = nil
        landed = nil
    }

    // MARK: 小工具

    /// 沿一道向上拱起的弧飞到 to（lift 是拱起多高）；lift 为 0 就走直线，和胶囊的路线一样
    private func fly(_ layer: CALayer, to: CGPoint, lift: CGFloat, duration: Double, delay: Double) {
        let from = (layer.presentation() ?? layer).position
        let path = CGMutablePath()
        path.move(to: from)
        if lift == 0 {
            path.addLine(to: to)
        } else {
            path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + lift))
        }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = duration
        // 不延迟就不写开始时间：新窗口第一帧上屏要一点时间，写了当前时间它就比胶囊先走一截
        if delay > 0 { move.beginTime = CACurrentMediaTime() + delay }
        move.fillMode = .both
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = to
        CATransaction.commit()
        layer.add(move, forKey: "fly")
    }

    /// 屏幕坐标 → 动画层里的坐标
    private func local(_ p: NSPoint) -> CGPoint {
        guard let f = window?.frame else { return p }
        return CGPoint(x: p.x - f.minX, y: p.y - f.minY)
    }

    private func local(_ r: NSRect) -> CGRect {
        CGRect(origin: local(r.origin), size: r.size)
    }

    private func animate(_ layer: CALayer, _ key: String, from: Any, to: Any, duration: Double, delay: Double = 0) {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        if delay > 0 { a.beginTime = CACurrentMediaTime() + delay }
        a.fillMode = .both
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(to, forKeyPath: key)
        CATransaction.commit()
        layer.add(a, forKey: key)
    }

    /// 胶囊变形：位置、大小、圆角一起动
    private func morph(_ layer: CALayer, to frame: CGRect, radius: CGFloat, duration: Double) {
        let from = layer.presentation() ?? layer
        let group = CAAnimationGroup()
        let pos = CABasicAnimation(keyPath: "position")
        pos.fromValue = NSValue(point: from.position)
        pos.toValue = NSValue(point: CGPoint(x: frame.midX, y: frame.midY))
        let size = CABasicAnimation(keyPath: "bounds")
        size.fromValue = NSValue(rect: from.bounds)
        size.toValue = NSValue(rect: CGRect(origin: .zero, size: frame.size))
        let corner = CABasicAnimation(keyPath: "cornerRadius")
        corner.fromValue = from.cornerRadius
        corner.toValue = radius
        group.animations = [pos, size, corner]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.2, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.cornerRadius = radius
        CATransaction.commit()
        layer.add(group, forKey: "morph")
    }

    /// 单色图标（模板图）上色；彩色的照原样
    private static func tinted(_ image: NSImage, tint: NSColor) -> CGImage? {
        let size = NSSize(width: 44, height: 44)
        let out = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if image.isTemplate {
                tint.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        return out.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
