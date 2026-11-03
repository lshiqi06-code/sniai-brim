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

/// 启动时装上的扩展
@MainActor
enum Extensions {
    static var boxAccessories: [BoxAccessory] = []
}
