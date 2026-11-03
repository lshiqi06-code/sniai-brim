import Foundation

/// 刘海旁边那棵像素云片松。a / b / c 是三片松叶（c 在最下面），t 是树干，n 是树梢上表示“需要你”的那一颗。
public enum Pine {
    public static let map: [String] = [
        ".....aaa...n..",
        "...aaaaaaa....",
        ".....aaaaaa...",
        ".......t......",
        "..bbbb.t......",
        "bbbbbbbb......",
        "..bbbbbt......",
        ".......t......",
        "......tcccc...",
        ".....tccccccc.",
        ".....t..cccc..",
        ".....t........",
        "....ttt.......",
    ]
    public static let width = 14
    public static let height = 13

    public enum Pixel: Sendable, Equatable { case leaf, glow, glowHi, trunk, ask }

    public struct Dot: Sendable, Equatable {
        public let x: Int
        public let y: Int
        public let pixel: Pixel
    }

    /// - busy: 几个在干活。几个就亮几片松叶，从下往上，最多三片。
    /// - ask: 有事等你，树梢那颗一闪一闪。
    /// - t: 秒，用来让蓝光流动。
    /// - grow: 从树根往上已经长出几行（-1 是还没长，≥12 是长全了）。
    public static func dots(busy: Int, ask: Bool, t: Double, grow: Int = .max, reduceMotion: Bool = false) -> [Dot] {
        let lit: [Character] = Array(["c", "b", "a"].prefix(max(0, min(3, busy))))
        let firstRow: [Character: Int] = ["a": 0, "b": 4, "c": 8]
        var out: [Dot] = []
        for (y, row) in map.enumerated() {
            guard height - 1 - y <= grow else { continue }
            for (x, c) in row.enumerated() {
                switch c {
                case ".":
                    continue
                case "t":
                    out.append(Dot(x: x, y: y, pixel: .trunk))
                case "n":
                    if ask && (reduceMotion || Int(t / 0.7) % 2 == 0) { out.append(Dot(x: x, y: y, pixel: .ask)) }
                default:
                    guard lit.contains(c) else { out.append(Dot(x: x, y: y, pixel: .leaf)); continue }
                    if reduceMotion {
                        out.append(Dot(x: x, y: y, pixel: y == firstRow[c] ? .glow : .leaf))
                        continue
                    }
                    // 一道蓝光从左往右慢慢流过这片叶子
                    var w = (Double(x) - t / 0.14 + Double(y) * 0.6).truncatingRemainder(dividingBy: 9)
                    if w < 0 { w += 9 }
                    out.append(Dot(x: x, y: y, pixel: w < 1.2 ? .glowHi : w < 2.6 ? .glow : .leaf))
                }
            }
        }
        return out
    }
}
