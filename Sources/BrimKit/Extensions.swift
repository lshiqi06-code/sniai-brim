import AppKit
import SwiftUI

/// 顶部面板展开后显示什么。开源版没有（只有一句提示）；并进 sniai yard 后由 yard 的客户端来填。
@MainActor
public protocol NotchContent: AnyObject {
    /// 启动时调一次
    func start()
    /// 松叶里亮几片（几个 agent 运行中）。实现是 @Observable 的话，界面会跟着变。
    var busyCount: Int { get }
    /// 面板将要展开：可以趁这时刷新
    func willExpand()
    /// 展开后的面板内容（宽度是 Theme.panelWidth，左右留白自己加）
    func panel() -> AnyView
    /// 右键顶部面板时，在“重播生长动画”下面多出来的几项
    func menuItems() -> AnyView
    /// 设置窗口里多出来的一页（侧栏排在“收纳”后面）；nil 就没有
    var settingsPage: ExtraSettingsPage? { get }
}

public struct ExtraSettingsPage {
    public let title: String
    public let symbol: String
    public let view: () -> AnyView

    public init(title: String, symbol: String, view: @escaping () -> AnyView) {
        self.title = title
        self.symbol = symbol
        self.view = view
    }
}

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
    static var notch: NotchContent?
    static var boxAccessories: [BoxAccessory] = []
}
