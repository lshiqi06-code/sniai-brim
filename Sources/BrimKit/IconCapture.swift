import AppKit
import BrimCore
import CryptoKit
import ScreenCaptureKit

/// 菜单栏图标本来的样子：趁它还在菜单栏上，截一小块存起来，收纳格里就用这张，不用应用的大图标。
/// 要“屏幕录制”权限，是可选的：没开就照旧用应用图标。只截菜单栏那一条，截的图只存在这台电脑上。
@MainActor
final class IconCapture {
    static let shared = IconCapture()

    private var cache: [String: NSImage] = [:]
    private var capturedAt: [String: Date] = [:]
    private var busy = false
    private let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("brim/menu-bar-icons", isDirectory: true)
    }()

    /// 一个图标多久重截一次（有的图标会变，比如代理连上 / 断开）
    static let refreshAfter: TimeInterval = 60

    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    private init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// 图标的认法换了以后，旧截图对不上号，全部删掉重截
    func forgetAll() {
        cache = [:]
        capturedAt = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// 截过的样子；没开权限或者还没截过就是 nil
    func image(for id: String) -> NSImage? {
        guard Self.allowed else { return nil }
        if let img = cache[id] { return img }
        guard let data = try? Data(contentsOf: file(id)), let rep = NSBitmapImageRep(data: data) else { return nil }
        let img = Self.image(from: rep)
        cache[id] = img
        return img
    }

    /// 截这些图标（必须是真的在菜单栏上看得到的：隐藏着的位置是旧的）。整条菜单栏截一次，再一个个裁出来。
    func capture(_ icons: [MenuBarIcon], force: Bool = false, then done: (() -> Void)? = nil) {
        let now = Date()
        let due = icons.filter { force || now.timeIntervalSince(capturedAt[$0.id] ?? .distantPast) > Self.refreshAfter }
        guard Self.allowed, !busy, !due.isEmpty, #available(macOS 15.2, *) else { done?(); return }
        busy = true
        let strip = due.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        Task { @MainActor in
            defer { self.busy = false; done?() }
            guard let shot = try? await SCScreenshotManager.captureImage(in: strip) else { return }
            let scale = CGFloat(shot.width) / strip.width
            for icon in due {
                let r = icon.frame.offsetBy(dx: -strip.minX, dy: -strip.minY)
                let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
                guard let crop = shot.cropping(to: px), let rep = Self.cutOut(crop) else { continue }
                self.cache[icon.id] = Self.image(from: rep)
                self.capturedAt[icon.id] = now
                try? rep.representation(using: .png, properties: [:])?.write(to: self.file(icon.id))
            }
        }
    }

    private func file(_ id: String) -> URL {
        let name = SHA256.hash(data: Data(id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name + ".png")
    }

    /// 截下来的是图标加菜单栏底色。把底色抠掉：离底色越近越透明。
    /// 菜单栏上大部分图标是单色的（系统按深浅自动变黑白），这种存成“模板图”，在浅色、深色菜单里都看得清。
    private static func cutOut(_ image: CGImage) -> NSBitmapImageRep? {
        let w = image.width, h = image.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        ctx.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let p = rep.bitmapData else { return nil }
        // 不猜底色，按亮度抠：菜单栏上的图标在深色菜单栏上接近纯白、在浅色菜单栏上接近纯黑，
        // 菜单栏本身（透着壁纸）和有的图标背后那块胶囊形的底都暗得多（或亮得多）。
        // 先看整张偏暗还是偏亮，判断菜单栏是深色还是浅色
        func lum(_ o: Int) -> Double { 0.299 * Double(p[o]) + 0.587 * Double(p[o + 1]) + 0.114 * Double(p[o + 2]) }
        let sorted = (0..<(w * h)).map { lum($0 * 4) }.sorted()
        let dark = sorted[sorted.count / 2] < 128
        for i in 0..<(w * h) {
            let o = i * 4
            let l = lum(o)
            let a = min(1, max(0, dark ? (l - 130) / 80 : (125 - l) / 80))
            // 位图是“预乘透明度”的，颜色要跟着乘
            for c in 0..<3 { p[o + c] = UInt8(Double(p[o + c]) * a) }
            p[o + 3] = UInt8(a * 255)
        }
        // 一大半都不透明，多半是截到了图标被按下时的高亮块，这张不要，下次再截
        let solid = (0..<(w * h)).filter { p[$0 * 4 + 3] > 128 }.count
        if solid * 10 > w * h * 6 { return nil }
        // 菜单栏底边那条分隔线会一起截进来：横贯整宽（97% 以上）的一行就是它，清掉；输入法、电池这类图标宽不到这么多
        for y in 0..<h where (0..<w).filter({ p[(y * w + $0) * 4 + 3] > 80 }).count * 100 > w * 97 {
            for x in 0..<w { for c in 0..<4 { p[(y * w + x) * 4 + c] = 0 } }
        }
        return trimmed(rep)
    }

    /// 裁掉四周透明的空白（留 2 像素），不然图标在收纳格里显得小
    private static func trimmed(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let p = rep.bitmapData, let cg = rep.cgImage else { return rep }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where p[(y * w + x) * 4 + 3] > 20 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= minX else { return nil }
        let box = CGRect(x: max(0, minX - 2), y: max(0, minY - 2), width: min(w, maxX + 3) - max(0, minX - 2), height: min(h, maxY + 3) - max(0, minY - 2))
        return cg.cropping(to: box).map(NSBitmapImageRep.init(cgImage:))
    }

    private static func image(from rep: NSBitmapImageRep) -> NSImage {
        // 存的是 2 倍像素，按点算大小
        let img = NSImage(size: NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2))
        img.addRepresentation(rep)
        img.isTemplate = isMonochrome(rep)
        return img
    }

    /// 几乎没有彩色像素的就当单色图标
    private static func isMonochrome(_ rep: NSBitmapImageRep) -> Bool {
        guard let p = rep.bitmapData else { return false }
        var colorful = 0, solid = 0
        for i in 0..<(rep.pixelsWide * rep.pixelsHigh) {
            let o = i * 4
            guard p[o + 3] > 128 else { continue }
            solid += 1
            let a = Double(p[o + 3]) / 255
            let rgb = (0..<3).map { Int(Double(p[o + $0]) / a) }
            if rgb.max()! - rgb.min()! > 40 { colorful += 1 }
        }
        return solid > 0 && colorful * 20 < solid
    }
}
