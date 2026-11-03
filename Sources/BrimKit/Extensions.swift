import AppKit

/// 收纳格面板里，图标下面多出来的一块（比如待办清单）。
@MainActor
public protocol BoxAccessory: AnyObject {
    /// 这个收纳格带不带。firstBox 是排在第一个的收纳格。实现是 @Observable 的话，设置页会跟着变。
    func shows(in box: String, firstBox: String?) -> Bool
    func setShows(_ on: Bool, in box: String, firstBox: String?)
    /// 设置“收纳”页每个格子后面那个勾选的名字和说明
    var toggleTitle: String { get }
    var toggleHelp: String { get }
    /// 面板里的那一块，宽度至少是 width
    func makeView(width: CGFloat) -> NSView
}

/// 收纳格多出来的一种样子（比如图标包里的一个）。像素图一行一个字符串，x 是实心、. 是空，最多 10×10 格（每格 1.5 点）。
public struct BoxGlyph: Sendable {
    /// 存在设置里的名字，别和自带的重名（加个前缀，比如 "yard.kite"）
    public let id: String
    public let zh: String
    public let en: String
    public let pixels: [String]

    public init(id: String, zh: String, en: String, pixels: [String]) {
        self.id = id
        self.zh = zh
        self.en = en
        self.pixels = pixels
    }
}

/// 启动时装上的扩展
@MainActor
enum Extensions {
    static var boxAccessories: [BoxAccessory] = []
    static var glyphs: [BoxGlyph] = []
}
