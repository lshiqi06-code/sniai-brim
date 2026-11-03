import AppKit
import BrimCore
import Observation
import ServiceManagement
import SwiftUI

/// 设置窗口左边的几页（照 design/brim-design.html 的“brim 的设置窗口”，只放现在真能用的项）。
/// agents 那一页由扩展提供（NotchContent.settingsPage），没装扩展就没有。
enum SettingsPage: String, CaseIterable, Identifiable {
    case notch, stash, agents, permissions, general
    /// 侧栏按 id 认选中的是哪一行，id 就用这一页本身，和侧栏选中的值同一类型，点了才切得过去
    var id: Self { self }

    @MainActor var title: String {
        switch self {
        case .notch: L("顶部面板", "Top Panel")
        case .stash: L("收纳", "Stash")
        case .agents: Extensions.notch?.settingsPage?.title ?? "Agent"
        case .permissions: L("权限", "Permissions")
        case .general: L("通用", "General")
        }
    }

    @MainActor var symbol: String {
        switch self {
        case .notch: "rectangle.topthird.inset.filled"
        case .stash: "tray"
        case .agents: Extensions.notch?.settingsPage?.symbol ?? "puzzlepiece"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        }
    }

    /// 侧栏上真有的几页
    @MainActor static var shown: [SettingsPage] {
        allCases.filter { $0 != .agents || Extensions.notch?.settingsPage != nil }
    }
}

@MainActor @Observable
final class SettingsNav {
    var page: SettingsPage? = .notch
}

/// 开机自动打开：用系统的登录项。要用户在系统设置里点“允许”时，状态是 requiresApproval。
@MainActor @Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }

    func refresh() { status = SMAppService.mainApp.status }
}

/// brim 的设置窗口。平时用不着：右键帽檐或刘海选“设置…”才出来。
@MainActor
final class SettingsWindow {
    static weak var shared: SettingsWindow?

    private let nav = SettingsNav()
    private let login = LoginItem()
    private let stash: MenuBarStash
    private let notch: NotchModel
    private var window: NSWindow?

    init(stash: MenuBarStash, notch: NotchModel) {
        self.stash = stash
        self.notch = notch
        Self.shared = self
    }

    func show(_ page: SettingsPage? = nil) {
        if let page, SettingsPage.shown.contains(page) { nav.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = L("brim 设置", "brim Settings")
            w.identifier = NSUserInterfaceItemIdentifier("brim.settings")
            // 有工具栏，侧栏才会用系统的玻璃，和系统设置一个样子
            w.toolbar = NSToolbar(identifier: "brim.settings")
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(nav: nav, login: login, stash: stash, notch: notch))
            w.setFrameAutosaveName("brim.settings")
            if !w.setFrameUsingName("brim.settings") { w.center() }
            window = w
        }
        login.refresh()
        stash.refreshIcons()
        // 新版 macOS 不让后台应用自己抢到最前面，所以先“不管别人”地摆到最前，再让它能打字
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKey()
    }
}

struct SettingsView: View {
    @Bindable var nav: SettingsNav
    let login: LoginItem
    let stash: MenuBarStash
    @Bindable var notch: NotchModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.shown, selection: $nav.page) { page in
                Label(page.title, systemImage: page.symbol)
                    .badge(page == .permissions ? permissionsToDo : 0)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch nav.page ?? .notch {
            case .notch: notchPage
            case .stash: OrganizerView(stash: stash)
            case .agents: Extensions.notch?.settingsPage?.view() ?? AnyView(EmptyView())
            case .permissions: permissionsPage
            case .general: generalPage
            }
        }
        .frame(minWidth: 700, minHeight: 540)
    }

    /// 换语言：界面马上换；菜单栏上收纳格的提示文字也跟着换
    private func setLanguage(_ choice: Lang.Choice) {
        Lang.shared.choice = choice
        stash.languageChanged()
        NSApp.windows.first { $0.identifier?.rawValue == "brim.settings" }?.title = L("brim 设置", "brim Settings")
    }

    /// 还差几样没打开（侧栏“权限”上的小数字）
    private var permissionsToDo: Int {
        (stash.trusted ? 0 : 1) + (AppLocation.isInApplications ? 0 : 1)
    }

    // MARK: 刘海

    private var notchPage: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { notch.side }, set: { notch.side = $0; notch.startGrow() })) {
                    Text(L("左侧", "Left")).tag(PineSide.left)
                    Text(L("右侧", "Right")).tag(PineSide.right)
                } label: {
                    Text(L("松树位置", "Pine position"))
                    Text(L("更改后松树会在新的一侧重新播放生长动画", "The pine replays its growth animation on the new side"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker(selection: $notch.openDelay) {
                    ForEach([0.2, 0.3, 0.5, 0.8], id: \.self) { s in Text(L("\(s.formatted()) 秒", "\(s.formatted()) s")).tag(s) }
                } label: {
                    Text(L("展开前的停留时间", "Delay before opening"))
                    Text(L("太短的话，鼠标经过时容易误展开", "Too short and it opens when the pointer just passes by"))
                }
                .fixedSize()
            }
            Section {
                Button(L("重播生长动画", "Replay Growth Animation")) { notch.startGrow() }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 权限

    private var permissionsPage: some View {
        Form {
            Section {
                LabeledContent {
                    if stash.trusted {
                        Text(L("已打开", "On")).foregroundStyle(.secondary)
                    } else {
                        Button(L("前往打开", "Turn On…")) { PermissionGuide.show(.accessibility) }
                    }
                } label: {
                    Text(L("辅助功能", "Accessibility"))
                    Text(L("收纳功能需要：读取菜单栏上的图标并替你打开。不开启的话顶部面板照常可用，收纳不可用。", "Needed for Stash: reading menu bar icons and opening them for you. Without it the top panel still works, but Stash doesn't."))
                }
                LabeledContent {
                    if AppLocation.isInApplications {
                        Text(L("已安装", "Installed")).foregroundStyle(.secondary)
                    } else {
                        Button(L("移到“应用程序”", "Move to Applications")) { AppLocation.offerMoveIfNeeded() }
                    }
                } label: {
                    Text(L("安装在“应用程序”文件夹中", "Installed in Applications"))
                    Text(L("隐藏图标需要 brim 安装在这里，系统才能识别 brim 自己的收纳格。", "brim must be installed there for the system to recognize its own boxes when hiding icons."))
                }
            }
            Section {
                LabeledContent {
                    if IconCapture.allowed {
                        Text(L("已打开", "On")).foregroundStyle(.secondary)
                    } else {
                        Button(L("前往打开", "Turn On…")) { PermissionGuide.show(.screenRecording) }
                    }
                } label: {
                    Text(L("屏幕录制（可选）", "Screen Recording (optional)"))
                    Text(L("让收纳格里显示图标在菜单栏上本来的样子。只截菜单栏那一小条，截图只存在这台电脑上。不打开就显示应用图标。", "Shows icons in boxes the way they look in the menu bar. brim captures only the thin menu bar strip, and captures stay on this Mac. Without it, boxes show app icons."))
                }
            } footer: {
                Text(L("只有“辅助功能”是必需的。如果有提示要求“完全磁盘访问权限”，那不是 brim 发出的。", "Only Accessibility is required. If you're asked for Full Disk Access, that request isn't from brim."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 通用

    private var generalPage: some View {
        Form {
            Section {
                Picker(L("语言", "Language"), selection: Binding(get: { Lang.shared.choice }, set: { setLanguage($0) })) {
                    Text(L("跟随系统", "System")).tag(Lang.Choice.system)
                    Text("中文").tag(Lang.Choice.zh)
                    Text("English").tag(Lang.Choice.en)
                }
                .fixedSize()
                Toggle(isOn: Binding(get: { login.isOn }, set: { login.set($0) })) {
                    Text(L("登录时打开", "Open at login"))
                    if login.status == .requiresApproval {
                        Text(L("还差一步：在“系统设置” › “通用” › “登录项”中允许 brim", "One more step: allow brim in System Settings › General › Login Items"))
                    }
                }
                if login.status == .requiresApproval {
                    Button(L("打开登录项设置", "Open Login Items Settings")) { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = login.error {
                    Text(L("设置失败：\(error)", "Couldn't set it: \(error)")).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent(L("版本", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                Button(L("退出 brim", "Quit brim")) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}
