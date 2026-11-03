import AppKit
import BrimCore

/// brim 没有 Dock 图标，只有菜单栏上的收纳格（帽檐）。退出：右键收纳格 → 退出 brim。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var stash: MenuBarStash?
    var settings: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stash = MenuBarStash()
        self.stash = stash
        settings = SettingsWindow(stash: stash)
        // 收纳格要用“辅助功能”权限读菜单栏图标；没有的话请系统弹一次授权提示
        if !MenuBarItems.trusted { MenuBarItems.askForPermission() }
        PermissionGuide.resumeIfPending()
        AppLocation.offerMoveIfNeeded()
        // brim --settings [哪一页：stash / permissions / general]：一打开就显示设置窗口，看设置界面时用
        if let i = CommandLine.arguments.firstIndex(of: "--settings") {
            let page = CommandLine.arguments.dropFirst(i + 1).first.flatMap(SettingsPage.init(rawValue:))
            settings?.show(page)
        }
    }
}

public enum BrimApp {
    /// 开起来。boxAccessories 是收纳格面板里图标下面多出来的几块；开源版不传。
    @MainActor
    public static func run(boxAccessories: [BoxAccessory] = []) -> Never {
        Extensions.boxAccessories = boxAccessories
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }
}
