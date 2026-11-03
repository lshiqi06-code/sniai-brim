import BrimCore
import SwiftUI

/// 颜色是 sniai yard 院子色的深色那一套（都是临时值）。刘海永远是黑底，所以只用深色。
public enum Theme {
    public static let notch = Color.black
    public static let ink = Color(hex: 0xDBEBE5)
    public static let dim = Color(hex: 0x7A948C)
    public static let line = Color(hex: 0xDBEBE5).opacity(0.12)
    public static let hot = Color(hex: 0x6B8CFF)
    public static let hotHi = Color(hex: 0xA9BCFF)
    public static let leaf = Color(hex: 0x53B39A)
    public static let trunk = Color(hex: 0x3D5650)
    public static let mute = Color(hex: 0x3D5650)
    public static let lcd = Color(hex: 0x0F201C)
    public static let track = Color(hex: 0x1C3D36)
    public static let bad = Color(hex: 0xFF8A80)

    public static let slotWidth: CGFloat = 36
    public static let panelWidth: CGFloat = 500

    /// 院子窗的天色跟着本机时间走
    public static func sky(at date: Date = .now) -> (name: String, color: Color) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        switch h {
        case 5..<8: return (L("清晨", "Dawn"), Color(hex: 0x16211F))
        case 8..<17: return (L("白天", "Day"), Color(hex: 0x0F1E1B))
        case 17..<19.5: return (L("傍晚", "Dusk"), Color(hex: 0x121A20))
        default: return (L("夜间", "Night"), Color(hex: 0x070C0B))
        }
    }
}

extension Color {
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
