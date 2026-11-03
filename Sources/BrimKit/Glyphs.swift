import AppKit
import BrimCore

/// 收纳格可以挑的样子。前几个是 brim 自己画的像素小图（院子里的东西），后几个用系统图标。
@MainActor
enum Glyph {
    static var options: [(id: String, name: String)] { [
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

    static let symbols: [String: String] = [
        "network": "network", "tools": "wrench.and.screwdriver", "sparkles": "sparkles",
        "tray": "tray", "briefcase": "briefcase",
    ]

    /// 菜单栏用的小图（模板图，跟着系统深浅色变）
    static func image(_ id: String, open: Bool = false) -> NSImage {
        if id == "eave" { return MenuBarStash.eave(dots: !open) }
        if let name = symbols[id], let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let sized = img.withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? img
            sized.isTemplate = true
            return sized
        }
        let map = pixelMaps[id] ?? pixelMaps["stone"]!
        let cols = map.map(\.count).max() ?? 1
        let unit = min(1.6, 16.0 / Double(cols), 14.0 / Double(map.count))
        let w = Double(cols) * unit, h = Double(map.count) * unit
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let ox = (16 - w) / 2, oy = (16 - h) / 2
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
