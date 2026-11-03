import AppKit
import BrimCore
import SwiftUI

/// 画那棵像素松。没事的时候不动，省电；有 agent 在干活或者等你时才每秒刷新 20 次。
/// 松画在一个 AppKit 小图层里，每一帧只换这一小块的图：用 SwiftUI 的 TimelineView 逐帧画时，
/// 整个顶部面板窗口跟着重排，有 agent 在干活时 brim 常驻约 7% CPU。
public struct PineView: View {
    var busy: Int
    var ask: Bool
    var grow: Int = .max

    public init(busy: Int, ask: Bool, grow: Int = .max) {
        self.busy = busy
        self.ask = ask
        self.grow = grow
    }

    public var body: some View {
        PineLayer(busy: busy, ask: ask, grow: grow)
            .aspectRatio(CGFloat(Pine.width) / CGFloat(Pine.height), contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel(busy > 0 ? L("\(busy) 个 agent 运行中", "\(busy) agents working") : L("agent 全部空闲", "All agents idle"))
    }
}

private struct PineLayer: NSViewRepresentable {
    var busy: Int
    var ask: Bool
    var grow: Int

    func makeNSView(context: Context) -> PineLayerView { PineLayerView() }

    func updateNSView(_ view: PineLayerView, context: Context) {
        view.set(busy: busy, ask: ask, grow: grow)
    }
}

/// 松的图层：算出这一刻亮哪些点，和上一帧一样就不重画
final class PineLayerView: NSView {
    private var busy = 0
    private var ask = false
    private var grow = Int.max
    private var timer: Timer?
    private var drawn: [Pine.Dot]?

    private static let colors: [Pine.Pixel: CGColor] = [
        .leaf: NSColor(Theme.leaf).cgColor,
        .glow: NSColor(Theme.hot).cgColor,
        .glowHi: NSColor(Theme.hotHi).cgColor,
        .trunk: NSColor(Theme.trunk).cgColor,
        .ask: NSColor(Theme.hot).cgColor,
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionChanged),
                                                          name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func set(busy: Int, ask: Bool, grow: Int) {
        guard busy != self.busy || ask != self.ask || grow != self.grow else { return }
        self.busy = busy
        self.ask = ask
        self.grow = grow
        updateTimer()
        redraw()
    }

    @objc private func motionChanged() {
        updateTimer()
        redraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
        redraw(force: true)
    }

    override func layout() {
        super.layout()
        redraw(force: true)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw(force: true)
    }

    /// 只在要动的时候走表；不在窗口里时停掉
    private func updateTimer() {
        let animate = window != nil && (busy > 0 || ask) && !reduceMotion
        if animate, timer == nil {
            let t = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.redraw() }
            }
            t.tolerance = 0.01
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !animate {
            timer?.invalidate()
            timer = nil
        }
    }

    /// 和 SwiftUI 的 Canvas 一样的画法：左上角起，每个点 px 大小
    private func redraw(force: Bool = false) {
        let dots = Pine.dots(busy: busy, ask: ask, t: Date().timeIntervalSinceReferenceDate, grow: grow, reduceMotion: reduceMotion)
        guard force || dots != drawn, let layer else { return }
        drawn = dots
        let scale = window?.backingScaleFactor ?? 2
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        // 位图的原点在左下，翻成左上
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        let px = min(bounds.width / CGFloat(Pine.width), bounds.height / CGFloat(Pine.height))
        for d in dots {
            ctx.setFillColor(Self.colors[d.pixel] ?? NSColor.white.cgColor)
            ctx.fill(CGRect(x: CGFloat(d.x) * px, y: CGFloat(d.y) * px, width: px, height: px))
        }
        layer.contentsScale = scale
        layer.contents = ctx.makeImage()
    }
}
