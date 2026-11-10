import AppKit
import BrimCore

/// 收纳格可以挑的样子。前几个是 brim 自己画的像素小图（院子里的东西），后几个用系统图标；
/// 扩展（Extensions.glyphs，比如收费版的图标包）多出来的排在最后。
/// 这里的像素图不在 MIT 许可范围内，见 BRAND.md。
@MainActor
enum Glyph {
    static var options: [(id: String, name: String)] { base + Extensions.glyphs.map { ($0.id, L($0.zh, $0.en)) } }

    private static var base: [(id: String, name: String)] { [
        ("eave", L("帽檐", "Brim")), ("pine", L("松树", "Pine")), ("lantern", L("石灯笼", "Lantern")), ("fish", L("鱼", "Fish")),
        ("stone", L("石头", "Stone")), ("network", L("网络", "Network")), ("tools", L("工具", "Tools")), ("sparkles", "AI"),
        ("tray", L("抽屉", "Tray")), ("briefcase", L("工作", "Work")),
    ] }

    static let pixelMaps: [String: [String]] = [
        "pine": [
            "..xxxx...",
            "xxxxxxx..",
            "....x....",
            ".xxxxx...",
            "xxxxxxx..",
            "....x.xx.",
            "...xxxxxx",
            "....x....",
            "...xxx...",
        ],
        "lantern": [
            "..xxx..",
            ".xxxxx.",
            "..x.x..",
            "..xxx..",
            "...x...",
            "..xxx..",
            ".xxxxx.",
        ],
        "fish": [
            "...xxx...x",
            ".xxxxxx.xx",
            "xx.xxxxxx.",
            ".xxxxxx.xx",
            "...xxx...x",
        ],
        "stone": [
            "...xxx...",
            ".xxxxxxx.",
            "xxxxxxxxx",
            "xxxxxxxxx",
            ".xxxxxxx.",
        ],
    ]

    /// 帽檐：一道屋檐，下面三个小方块
    private static var eave: NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let roof = NSBezierPath()
            roof.move(to: NSPoint(x: 1.5, y: 8))
            roof.line(to: NSPoint(x: 8, y: 3))
            roof.line(to: NSPoint(x: 14.5, y: 8))
            roof.lineWidth = 1.6
            roof.lineJoinStyle = .miter
            roof.stroke()
            for x in [3.5, 7.0, 10.5] { NSRect(x: x, y: 10.5, width: 2, height: 2).fill() }
            return true
        }
        img.isTemplate = true
        return img
    }

    static let symbols: [String: String] = [
        "network": "network", "tools": "wrench.and.screwdriver", "sparkles": "sparkles",
        "tray": "tray", "briefcase": "briefcase",
    ]

    /// 菜单栏用的小图（模板图，跟着系统深浅色变）
    static func image(_ id: String) -> NSImage {
        if id == "eave" { return eave }
        if let name = symbols[id], let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let sized = img.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? img
            sized.isTemplate = true
            return sized
        }
        let map = pixelMaps[id] ?? Extensions.glyphs.first { $0.id == id }?.pixels ?? pixelMaps["stone"]!
        let cols = map.map(\.count).max() ?? 1
        // 每格 1.5 点（视网膜屏上正好 3 个像素），左上角落在半点上：边缘不糊。放不下（超过 10 格）才缩小
        let unit = min(1.5, 16.0 / Double(cols), 16.0 / Double(map.count))
        let w = Double(cols) * unit, h = Double(map.count) * unit
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let ox = ((16 - w) / 2 * 2).rounded() / 2, oy = ((16 - h) / 2 * 2).rounded() / 2
            for (y, row) in map.enumerated() {
                for (x, c) in row.enumerated() where c == "x" {
                    NSRect(x: ox + Double(x) * unit, y: oy + Double(y) * unit, width: unit, height: unit).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
