import AppKit
import BrimCore
import Observation
import OSLog
import SwiftUI

/// 见过的一个菜单栏图标。用户在系统设置里把它关掉以后，菜单栏上就读不到它了，所以要记住它是谁。
struct KnownIcon: Codable, Identifiable, Equatable {
    let id: String
    let appName: String
    let bundleID: String?
    let label: String

    init(_ icon: MenuBarIcon) {
        id = icon.id
        appName = icon.appName
        bundleID = icon.bundleID
        label = icon.label
    }

    /// 给人看的名字：系统图标用它自己的说明（“简体拼音”“搜索”），别的应用用应用名
    var displayName: String {
        if bundleID?.hasPrefix("com.apple.") == true { return label.isEmpty ? L("系统图标", "System icon") : label }
        return appName.replacingOccurrences(of: "AppLauncher", with: "").replacingOccurrences(of: "Launcher", with: "")
    }
}

/// 菜单栏收纳：用户自己建几个收纳格，每个格子挑一个样子，把菜单栏图标按自己的习惯放进去。
///
/// 怎么藏：用系统的“菜单栏显示限制”（见 MenuBarRestriction），名单外的应用由系统藏起来、重新排好，不会出现“«”。
/// 系统按应用藏，所以同一个应用的图标一起藏、一起露；苹果自己的图标藏不了。brim 退出或崩溃时菜单栏自动还原。
/// 点格子里藏着的图标：先让那个应用露出来，替你点开它的菜单，菜单关掉后再藏回去。
/// 读图标和替你点要“辅助功能”权限；藏本身不要权限，但 brim 要装在“应用程序”文件夹里。
private let log = Logger(subsystem: "net.lblus.brim", category: "stash")

@MainActor @Observable
final class MenuBarStash {
    private(set) var config: StashConfig?
    /// 见过的所有图标（包括已经在系统设置里关掉、现在看不到的）
    private(set) var known: [KnownIcon] = []
    /// 现在菜单栏上真的看得到的
    private(set) var live: [MenuBarIcon] = []
    /// 有没有“辅助功能”权限。用户在系统设置里打开以后，不用重启 brim 就能用
    private(set) var trusted = MenuBarItems.trusted

    @ObservationIgnored private var boxItems: [String: NSStatusItem] = [:]
    @ObservationIgnored private var watch: Timer?
    /// 藏不了的原因（不是 macOS 27、brim 不在“应用程序”里、系统拒绝），没问题就是 nil
    private(set) var hidingProblem: String?
    /// 正在通话（摄像头或麦克风在用）：暂时不隐藏，让系统的通话、摄像头胶囊显示出来
    private(set) var pausedForCall = false
    /// 通话时暂停收纳，设置里能关
    var pauseInCalls: Bool = UserDefaults.standard.object(forKey: "stash.pauseInCalls") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(pauseInCalls, forKey: "stash.pauseInCalls")
            checkCall()
        }
    }
    @ObservationIgnored private var callWatch: Timer?
    /// 读到过菜单的应用（记在本机设置里）。从没读到过的，就是“菜单只能挂在自己图标上”的那类：
    /// 在收纳格里点它，只能让图标回到菜单栏原位再点，菜单也只会从那里弹出，所以建议留在菜单栏上。
    /// 有的应用（Clash Verge）要右键过一次才把菜单挂上，读到过一次就记住，不会被误认。
    private(set) var mirrorable = Set(UserDefaults.standard.stringArray(forKey: "stash.mirrorable") ?? [])

    /// 点了才生成菜单、但生成以后读得出来的（记的是“应用|L”“应用|R”，左键右键分开记：Claude 右键是菜单、左键是窗口）。
    /// 第一次照常用动画在菜单栏上打开，那时发现它的菜单读得出来就记下；以后在整屏幕帘底下点开、读出来、关掉，
    /// 再从收纳格那一格下面弹一份一样的，菜单栏不动
    @ObservationIgnored private var dynamicMenus = Set(UserDefaults.standard.stringArray(forKey: "stash.dynamicMenus") ?? [])

    /// 打开“菜单只能挂在自己图标上”的 app 时用哪种动画。放在这里界面才会跟着变（存在本机设置里）
    var handoffStyle = HandoffStyle.current {
        didSet { HandoffStyle.current = handoffStyle }
    }

    /// 现在开着面板的是哪个收纳格
    @ObservationIgnored private var openBox: String?
    /// 要在冻住的菜单栏上演“从收纳格到它的位置”的那一下：图标、上什么色、从哪一格出发、面板和帽檐在哪
    @ObservationIgnored private var pendingHandoff: (image: NSImage, tint: NSColor, cell: NSRect, panel: NSRect, box: NSRect, guess: NSRect?)?
    /// 启动时先截图再隐藏：截完之前不隐藏
    @ObservationIgnored private var holdHiding = false
    @ObservationIgnored private let restriction = MenuBarRestriction()
    @ObservationIgnored private var lastAllowed: Set<String>?
    /// 正在临时露出来、等用户用完它菜单的应用
    @ObservationIgnored private var peeking: String?
    @ObservationIgnored private var peekWatch: Timer?
    @ObservationIgnored private var clickMonitor: Any?

    static let configKey = "stash.v1"
    static let knownKey = "stash.known"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.configKey) { config = try? JSONDecoder().decode(StashConfig.self, from: data) }
        if let data = d.data(forKey: Self.knownKey) { known = (try? JSONDecoder().decode([KnownIcon].self, from: data)) ?? [] }
        migrateIconIDs()
        cleanStaleRecords()
        // 对方应用卡着时最多等半秒（默认 6 秒，brim 的主线程会跟着卡）
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        if trusted { MenuMirror.releaseStuckMenus() }
        syncBoxItems()
        // 刚启动时菜单栏上的图标都还看得见：开了“屏幕录制”的话先把它们的样子截下来，再隐藏
        if trusted && IconCapture.allowed {
            holdHiding = true
            // 上一个 brim 刚退出时，隐藏过的图标正在回到菜单栏（有一段动画），等它们停稳再截
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let all = MenuBarItems.scan().filter { $0.frame.width > 0 && $0.frame.minY < 40 }
                    IconCapture.shared.capture(all, force: true) { [weak self] in
                        self?.holdHiding = false
                        self?.applyHiding()
                    }
                }
            }
        } else {
            applyHiding()
        }
        // 新打开的应用不在放行名单里，会被一起藏掉：每打开一个应用就重新排一次名单
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyHiding() }
            // 等它把菜单栏图标放好，再认一遍
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { self?.refreshIcons() } }
        }

        // 等菜单栏排好再读；第一次用就打开整理窗口让用户自己挑
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.firstLook() }
        }
        // 每 3 秒看一眼：权限有没有打开、用户在系统设置里关掉了哪几个
        watch = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.trusted, MenuBarItems.trusted { self.trusted = true }
                // 打开着别的应用的菜单时不读：读辅助功能要等对方回话，不能耽误“菜单关了就收回”
                if self.peeking == nil, NSApp.keyWindow?.identifier?.rawValue == "brim.settings" { self.refreshIcons() }
            }
        }
        callWatch = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCall() }
        }
    }

    /// 通话开始就把图标全放出来，结束了再收回去
    private func checkCall() {
        let inCall = pauseInCalls && MediaInUse.any
        guard inCall != pausedForCall else { return }
        pausedForCall = inCall
        log.info("\(inCall ? "通话开始，暂停收纳" : "通话结束，恢复收纳", privacy: .public)")
        applyHiding()
    }

    /// 旧版按“应用|说明文字”认图标，换了说明语言就多出一个。改成“应用|#第几个”：
    /// 每个应用原来放在哪还放在哪（隐藏本来就按应用算），见过的图标清空，下次读菜单栏时重新认。只做一次。
    private func migrateIconIDs() {
        guard known.contains(where: { !$0.id.contains("|#") }) else { return }
        if var c = config {
            var place: [String: StashConfig.Place] = [:]
            for k in known where StashConfig.canHide(k.id) {
                let app = StashConfig.app(of: k.id)
                let p = c.place(of: k.id)
                if place[app] == nil || p != .visible { place[app] = p }
            }
            c.visible = []
            c.assignment = [:]
            for (app, p) in place {
                for n in 0..<4 { c.set("\(app)|#\(n)", to: p) }
            }
            config = c
            save()
        }
        known = []
        UserDefaults.standard.removeObject(forKey: Self.knownKey)
        IconCapture.shared.forgetAll()
        log.info("图标的认法换了，按应用迁移了收纳设置")
    }

    /// 迁移时多写过几个备用编号（#1、#2、#3）：真实的图标已经选了“显示在菜单栏”，这些旧记录却还会让它继续隐藏，清掉
    private func cleanStaleRecords() {
        guard var c = config else { return }
        let knownIDs = Set(known.map(\.id))
        let shown = Set(c.visible.filter(knownIDs.contains).map(StashConfig.app))
        let stale = c.assignment.keys.filter { !knownIDs.contains($0) && shown.contains(StashConfig.app(of: $0)) }
        guard !stale.isEmpty else { return }
        stale.forEach { c.assignment[$0] = nil }
        config = c
        save()
    }

    private func firstLook() {
        refreshIcons()
        if config == nil {
            config = .starter
            // 第一次整理：菜单只能挂在自己图标上的应用先留在菜单栏上
            for icon in known where isOwnMenuOnly(icon) { config?.set(icon.id, to: .visible) }
            save()
            syncBoxItems()
            applyHiding()
            openOrganizer()
        }
    }

    // MARK: 收纳格

    /// 换了界面语言：重写菜单栏上收纳格的提示
    func languageChanged() { syncBoxItems() }

    private var boxes: [StashBox] { config?.boxes ?? [StashBox(id: "main", name: L("收纳", "Stash"), glyph: "eave")] }

    private func syncBoxItems() {
        for (id, item) in boxItems where !boxes.contains(where: { $0.id == id }) {
            NSStatusBar.system.removeStatusItem(item)
            boxItems[id] = nil
        }
        for box in boxes {
            let item = boxItems[box.id] ?? {
                let key = "NSStatusItem Preferred Position brim.box.\(box.id)"
                if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(1, forKey: key) }
                let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                i.autosaveName = "brim.box.\(box.id)"
                i.button?.target = self
                i.button?.action = #selector(boxClicked(_:))
                i.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                boxItems[box.id] = i
                return i
            }()
            item.button?.image = Glyph.image(box.glyph)
            item.button?.identifier = NSUserInterfaceItemIdentifier(box.id)
            item.button?.toolTip = L("\(box.name)：点击查看里面的图标，右键整理", "\(box.name): click to see its icons, right-click to organize")
        }
    }

    @objc private func boxClicked(_ sender: NSStatusBarButton) {
        guard let id = sender.identifier?.rawValue, let item = boxItems[id] else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            BoxPanel.current?.close()
            item.menu = settingsMenu()
            item.button?.performClick(nil)
            item.menu = nil
            return
        }
        // 再点一次同一个收纳格就收起
        if let open = BoxPanel.current, openBox == id {
            open.close()
            return
        }
        guard let button = item.button else { return }
        let panel = BoxPanel(content: boxContent(id), under: button)
        openBox = id
        panel.onClose = { [weak self] in self?.openBox = nil }
        panel.show()
    }

    private func settingsMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: L("整理收纳格…", "Organize Boxes…"), action: #selector(openOrganizerAction), keyEquivalent: "").target = self
        m.addItem(withTitle: L("设置…", "Settings…"), action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        m.addItem(.separator())
        m.addItem(withTitle: L("退出 brim", "Quit brim"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return m
    }

    /// 收纳格面板里从上到下的几块：图标格、（没开屏幕录制时）一行入口、扩展（BoxAccessory）
    private func boxContent(_ boxID: String) -> [NSView] {
        refreshIcons()
        // 只放正在运行的应用：退出了的应用在菜单栏上本来就没有图标
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let inBox = config.map { c in
            known.filter { c.place(of: $0.id) == .box(boxID) && StashConfig.canHide($0.id) && running.contains(StashConfig.app(of: $0.id)) }
        } ?? []
        let first = config?.boxes.first?.id
        let extras = Extensions.boxAccessories.filter { $0.shows(in: boxID, firstBox: first) }
        var views: [NSView] = []
        var width: CGFloat = 260
        if trusted && !inBox.isEmpty {
            let grid = IconGridView(icons: inBox) { [weak self] icon, right, view, cell in
                self?.pick(icon, right: right, in: view, cell: cell)
            }
            width = max(width, grid.frame.width)
            views.append(grid)
        } else if extras.isEmpty || !trusted {
            let text = trusted ? L("收纳格是空的，点击这里整理…", "This box is empty. Click to organize…") : L("请先允许 brim 使用辅助功能…", "Allow brim to use Accessibility first…")
            views.append(PanelLink(title: text, width: width) { [weak self] in
                BoxPanel.current?.close()
                self?.openOrganizer()
            })
        }
        if trusted && !inBox.isEmpty && !IconCapture.allowed {
            views.append(PanelLink(title: L("显示图标在菜单栏上的样子…", "Show icons as they look in the menu bar…"), width: width) {
                BoxPanel.current?.close()
                PermissionGuide.show(.screenRecording)
            })
        }
        for extra in extras {
            if !views.isEmpty { views.append(PanelSeparator(width: width)) }
            views.append(extra.makeView(width: width))
        }
        return views
    }

    @objc private func openOrganizerAction() { openOrganizer() }
    @objc private func openSettingsAction() { SettingsWindow.shared?.show() }

    // MARK: 读图标

    /// 读一遍菜单栏，把新见到的记下来。时钟、控制中心这些排在格子右边的系统固定图标不算。
    func refreshIcons(capture: Bool = true) {
        guard trusted else { return }
        let boxLeft = boxItems.values.compactMap { $0.button?.window?.frame.minX }.min() ?? .greatestFiniteMagnitude
        live = MenuBarItems.scan().filter { $0.frame.minX < boxLeft && $0.frame.width > 0 }
        for item in live where StashConfig.canHide(item.id) && !mirrorable.contains(StashConfig.app(of: item.id)) {
            if MenuMirror.openMenu(of: item.element) != nil { noteMirrorable(StashConfig.app(of: item.id)) }
        }
        let fresh = live.filter { icon in !known.contains { $0.id == icon.id } }.map(KnownIcon.init)
        if !fresh.isEmpty {
            // 第一次整理以后才装的应用，先露在外面，等用户自己决定（同一个应用已经藏着的照旧藏着）
            if var c = config {
                let hidden = hiddenApps
                for f in fresh where !hidden.contains(StashConfig.app(of: f.id)) && c.assignment[f.id] == nil && !c.visible.contains(f.id) {
                    c.set(f.id, to: .visible)
                }
                config = c
                save()
            }
            known += fresh
            if let data = try? JSONEncoder().encode(known) { UserDefaults.standard.set(data, forKey: Self.knownKey) }
            applyHiding() // 新认出的图标可能属于要隐藏的应用
        }
        // 看得见的顺手截下样子（隐藏着的位置是旧的，不截）
        if capture {
            IconCapture.shared.capture(live.filter { icon in
                let app = StashConfig.app(of: icon.id)
                return !(restriction.isActive && hiddenApps.contains(app) && peeking != app)
            })
        }
    }

    // MARK: 藏

    /// 设置里记着的也算（应用还没启动、图标还没认出来时，它一启动就直接隐藏）
    var hiddenApps: Set<String> {
        guard let config else { return [] }
        return config.hiddenApps(among: known.map(\.id) + Array(config.assignment.keys))
    }

    func isHidden(_ icon: KnownIcon) -> Bool {
        let app = StashConfig.app(of: icon.id)
        return hidingProblem == nil && !pausedForCall && hiddenApps.contains(app) && peeking != app
    }

    /// 按现在的设置重排一次放行名单：正在跑的应用、见过的应用、brim 自己，减去要藏的。没有要藏的就撤掉限制。
    private func applyHiding(then done: (() -> Void)? = nil) {
        guard !holdHiding else { done?(); return }
        var hide = hiddenApps
        if let peeking { hide.remove(peeking) }
        guard !hide.isEmpty, !pausedForCall else {
            restriction.clear()
            lastAllowed = nil
            hidingProblem = nil
            done?()
            return
        }
        guard MenuBarRestriction.isAvailable else {
            hidingProblem = L("这台 Mac 无法隐藏图标：需要 macOS 27 或更高版本。", "This Mac can't hide icons: macOS 27 or later is required.")
            return
        }
        guard AppLocation.isInApplications else {
            hidingProblem = L("brim 需要安装在“应用程序”文件夹中才能隐藏图标。", "brim needs to be in the Applications folder to hide icons.")
            return
        }
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        allowed.formUnion(known.map { StashConfig.app(of: $0.id) })
        allowed.subtract(hide)
        allowed.insert(Bundle.main.bundleIdentifier ?? "net.lblus.brim")
        guard allowed != lastAllowed || !restriction.isActive else { done?(); return }
        restriction.apply(allowing: Array(allowed)) { [weak self] error in
            guard let self else { return }
            self.lastAllowed = error == nil ? allowed : nil
            self.hidingProblem = error.map { L("系统拒绝了隐藏：\($0.localizedDescription)", "The system refused to hide icons: \($0.localizedDescription)") }
            done?()
        }
    }

    // MARK: 点格子里的图标

    /// 露在外面的直接替你点；隐藏着的先让它显示出来、等它停稳再点，菜单关掉后再隐藏；应用没在跑就打开它。
    /// 收纳格面板里点了一个图标，效果要和在菜单栏上点它一样，但菜单栏不动。对所有应用都一样：
    /// 1. 图标上挂着菜单（大部分应用）：读出来，从这一格正下方弹一份一样的，选哪项就在后台按哪项（只按菜单项，不按图标）。面板不收起：
    /// 选了一项面板跟着收起；按 Esc 或点空白只关它的菜单，回到面板。
    /// 2. 菜单是点了才生成的、以前读到过（dynamicMenus）：整屏盖一张幕帘，在底下真点开、读出来、关掉，再从这一格下面弹（见 openQuietly）。
    /// 3. 其余（弹的是面板、窗口，或者第一次遇到）：面板收起，冻住菜单栏后真点，用动画过渡（见 peekAndClick）。
    private func pick(_ icon: KnownIcon, right: Bool, in view: NSView, cell: NSRect) {
        endPeek()
        let app = StashConfig.app(of: icon.id)
        if isHidden(icon) {
            let items = MenuBarItems.scan(only: app)
            if let item = items.first(where: { $0.id == icon.id }) ?? items.first, let menu = MenuMirror.read(item) {
                log.info("点了 \(icon.id, privacy: .public)：读到菜单（\(menu.items.count) 项），从这一格下面弹")
                noteMirrorable(app)
                // 图标格是从上往下排的坐标：这一格的左下角
                if menu.popUp(positioning: nil, at: NSPoint(x: cell.minX, y: cell.maxY + 2), in: view) {
                    BoxPanel.current?.close()
                }
                return
            }
        }
        if isHidden(icon), dynamicMenus.contains(Self.dynamicKey(app, right)), IconCapture.allowed {
            return openQuietly(icon, right: right, in: view, cell: cell)
        }
        // 读不到菜单：先记下动画从哪出发，面板等菜单栏冻住、动画接上以后再收（见 peekAndClick）
        if isHidden(icon), let win = view.window, let id = openBox, let button = boxItems[id]?.button, let bw = button.window {
            let tint = Self.barTint(button)
            // 动画一开始就朝它要出现的位置去
            let guess = live.first(where: { $0.id == icon.id }).map { Self.cocoa(expectedFrame(of: $0)) }
            pendingHandoff = (iconImage(for: icon), tint, win.convertToScreen(view.convert(cell, to: nil)), win.frame,
                              bw.convertToScreen(button.convert(button.bounds, to: nil)), guess)
        } else {
            pendingHandoff = nil
            BoxPanel.current?.close()
        }
        DispatchQueue.main.async { [weak self] in self?.press(icon, right: right) }
    }

    private func press(_ icon: KnownIcon, right: Bool = false) {
        endPeek()
        let app = StashConfig.app(of: icon.id)
        log.info("点了 \(icon.id, privacy: .public)（\(right ? "右键" : "左键", privacy: .public)）：隐藏着=\(self.isHidden(icon)) 问题=\(self.hidingProblem ?? "无", privacy: .public)")
        guard NSRunningApplication.runningApplications(withBundleIdentifier: app).first != nil else {
            BoxPanel.current?.close()
            return launch(app)
        }
        guard isHidden(icon) else {
            refreshIcons(capture: false)
            if let item = live.first(where: { $0.id == icon.id }) { open(item, right: right) } else { NSSound.beep() }
            return
        }
        peekAndClick(icon, right: right)
    }

    /// 读不到菜单的隐藏图标：冻住菜单栏（盖一张照片），在底下让它真的出现、用你点的那个键真的点一下，用完收回再揭开照片。
    /// 和你在菜单栏上点它完全一样。不在图标隐藏时“后台按”它：各个应用的反应五花八门（面板开了却看不见、
    /// 停在看不见的菜单里、图标一直带着高亮），靠不住。
    private func peekAndClick(_ icon: KnownIcon, right: Bool) {
        // 先拍下菜单栏盖上去（开了屏幕录制才行），底下的变化你就看不到；
        // 冻住以后动画层接在收纳格面板上开始，再收起面板
        MenuBarFreeze.shared.freeze { [weak self] in
            guard let self else { return }
            if let h = self.pendingHandoff, MenuBarFreeze.shared.isFrozen {
                HandoffAnimator.shared.begin(image: h.image, tint: h.tint, cell: h.cell, panel: h.panel, box: h.box, guess: h.guess)
            }
            self.pendingHandoff = nil
            BoxPanel.current?.close(fade: true)
            self.peekUnderFreeze(icon, right: right)
        }
    }

    private func peekUnderFreeze(_ icon: KnownIcon, right: Bool) {
        let app = StashConfig.app(of: icon.id)
        let stale = live.first { $0.id == icon.id }?.frame
        peeking = app
        // 保险：系统 1.5 秒没让它显示出来，就算了（不在隐藏状态下去按它，那样各个应用的反应靠不住）
        var answered = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !answered, self.peeking == app else { return }
                log.error("显示限制没回应，没能打开 \(icon.id, privacy: .public)")
                NSSound.beep()
                self.endPeek()
            }
        }
        applyHiding { [weak self] in
            answered = true
            self?.waitUntilShown(icon, app: app, stale: stale, since: Date()) { item in
                // 动画落到它真正的位置，快到时再真的点它：菜单差不多在落位那一刻弹出来
                if HandoffAnimator.shared.isActive {
                    HandoffAnimator.shared.land(on: Self.cocoa(item.frame)) { self?.open(item, right: right) }
                } else {
                    self?.open(item, right: right)
                }
            }
        }
    }

    /// 菜单栏挪位置有一段动画：至少等 0.25 秒，再等它的位置连续两次读到一样（停稳了）；
    /// 它隐藏前后位置没变时读不出来有没有停稳，就只等 0.35 秒。最多等 2 秒。
    private func waitUntilShown(_ icon: KnownIcon, app: String, stale: CGRect?, since: Date, last: CGRect? = nil,
                                then: @escaping (MenuBarIcon) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.peeking == app else { return }
                let items = MenuBarItems.scan(only: app)
                let item = items.first(where: { $0.id == icon.id }) ?? items.first
                let waited = Date().timeIntervalSince(since)
                if let item, waited > 0.25, item.frame == last, item.frame != stale || waited > 0.35 {
                    return then(item)
                }
                if waited > 2 {
                    guard let item else {
                        log.error("显示出来以后没找到 \(icon.id, privacy: .public)")
                        NSSound.beep()
                        return self.endPeek()
                    }
                    return then(item)
                }
                self.waitUntilShown(icon, app: app, stale: stale, since: since, last: item?.frame, then: then)
            }
        }
    }

    /// 替你点开它（像人一样真的点一下），并且看着它的菜单：
    /// - 菜单、面板出现过又关了，就隐藏回去。
    /// - 2 秒什么都没弹出来，或者这期间你在别处点了一下，也隐藏回去。
    private func open(_ item: MenuBarIcon, right: Bool) {
        // 它这会儿在菜单栏上看得见：还没截过它本来的样子就先截一张（开了屏幕录制才截；点开以后图标底下有一块高亮，截出来不干净），截完再点。
        // 截过的就直接点，不让你多等
        guard IconCapture.shared.image(for: item.id) == nil else { return click(item, right: right) }
        IconCapture.shared.capture([item], force: true) { [weak self] in self?.click(item, right: right) }
    }

    private func click(_ item: MenuBarIcon, right: Bool) {
        let before = Self.popups(pid: item.pid, bundleID: item.bundleID)
        MenuBarItems.press(item, right: right)
        log.info("替你点了 \(item.id, privacy: .public)，位置 \(Int(item.frame.minX)),\(Int(item.frame.minY))")
        guard peeking != nil else { return }
        watchPopup(of: item, right: right, before: before)
    }

    /// 看着刚点开的菜单 / 面板，关了就收回（before 是点之前它已经开着的窗口，不算）
    private func watchPopup(of item: MenuBarIcon, right: Bool, before: Set<CGWindowID>) {
        let bundleID = item.bundleID
        // 辅助功能元素不能跨线程传；计时器的回调都在主线程上
        nonisolated(unsafe) let item = item
        var probed = false
        let pid = item.pid, frame = item.frame
        let start = Date()
        var sawMenu: Date?
        var goneSince: Date?
        let watch = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Self.popups(pid: pid, bundleID: bundleID).subtracting(before)
                let open = !now.isEmpty
                let elapsed = Date().timeIntervalSince(start)
                if open != (sawMenu != nil && goneSince == nil) {
                    log.info("\(String(format: "%.1f", elapsed), privacy: .public) 秒：弹出窗口\(open ? "出现" : "不见了", privacy: .public) \(Self.describe(now), privacy: .public)")
                }
                if open {
                    if sawMenu == nil { sawMenu = Date() }
                    goneSince = nil
                    // 顺便看一眼：它弹出的要是一份读得出来的菜单，记下来，下次直接从收纳格那一格下面弹
                    if !probed {
                        probed = true
                        if let app = bundleID, MenuMirror.readOpened(item) != nil { self.noteDynamic(app, right) }
                    }
                } else if let seen = sawMenu {
                    // 面板打开的过程中，窗口可能先闪一个再换成正式的：刚出现时连续 0.6 秒都不在才算真关了；
                    // 已经开了一会儿的，一关就收回
                    if let gone = goneSince {
                        let wait = gone.timeIntervalSince(seen) > 1 ? 0.15 : 0.6
                        if Date().timeIntervalSince(gone) > wait { self.endPeek() }
                    } else {
                        goneSince = Date()
                    }
                } else if elapsed > 2 {
                    // 2 秒什么都没弹出来：这个应用对这一下本来就没反应（比如有的应用右键什么都不做），
                    // 或者它打开的是普通窗口。马上收回，别让菜单栏一直冻着
                    log.info("点了以后没有弹出菜单或面板，收回")
                    self.endPeek()
                }
            }
        }
        // 主线程在处理鼠标拖动、菜单时也要走
        RunLoop.main.add(watch, forMode: .common)
        peekWatch = watch
        let me = Int64(ProcessInfo.processInfo.processIdentifier)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // 跳过 brim 自己刚模拟的那一下（它也会被这里听到，而且来得比菜单还晚）
            guard event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) != me else { return }
            // 用那一下点击本身的位置（左上角为原点，和辅助功能一样），不用“现在鼠标在哪”
            let top = event.cgEvent?.location ?? .zero
            MainActor.assumeIsolated {
                guard let self, sawMenu == nil else { return }
                if frame.insetBy(dx: -3, dy: -3).contains(top) { return }
                // 点菜单里的一项时，菜单要在松开鼠标那一下才执行，晚一点再隐藏
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { self.endPeek() } }
            }
        }
    }

    private func launch(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return NSSound.beep() }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private func endPeek() {
        if peeking != nil { log.info("收回 \(self.peeking ?? "", privacy: .public)") }
        peekWatch?.invalidate()
        peekWatch = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        guard peeking != nil else { return }
        peeking = nil
        applyHiding()
        MenuBarFreeze.shared.liftCurtain()
        // 动画回到帽檐；等底下的图标收回、菜单栏排好，再揭开照片
        if HandoffAnimator.shared.isActive {
            HandoffAnimator.shared.finish { if MenuBarFreeze.shared.isFrozen { MenuBarFreeze.shared.thaw(after: 0.6) } }
        } else if MenuBarFreeze.shared.isFrozen {
            MenuBarFreeze.shared.thaw()
        }
    }

    // MARK: 点了才生成的菜单

    private static func dynamicKey(_ app: String, _ right: Bool) -> String { "\(app)|\(right ? "R" : "L")" }

    private func noteDynamic(_ app: String, _ right: Bool, _ works: Bool = true) {
        let key = Self.dynamicKey(app, right)
        guard dynamicMenus.contains(key) != works else { return }
        if works { dynamicMenus.insert(key) } else { dynamicMenus.remove(key) }
        UserDefaults.standard.set(Array(dynamicMenus), forKey: "stash.dynamicMenus")
        log.info("\(key, privacy: .public)：\(works ? "菜单点开后读得出来，以后从收纳格下面弹" : "这次没读到菜单，改回用动画打开", privacy: .public)")
    }

    /// 菜单是点了才生成的：整屏盖一张幕帘（一张屏幕的照片，比菜单还高一层），在底下让图标回到菜单栏、真点开、
    /// 把菜单读出来、马上关掉、图标收回，再揭开幕帘，从收纳格这一格下面弹一份一样的。收纳格面板一直开着，菜单栏看着没动过。
    /// 没读到（这次弹的不是菜单）就揭开幕帘，照平常那样等它关了再收回，并且忘掉这条记录，下次用动画打开。
    private func openQuietly(_ icon: KnownIcon, right: Bool, in view: NSView, cell: NSRect) {
        let app = StashConfig.app(of: icon.id)
        MenuBarFreeze.shared.freezeWholeScreen { [weak self] covered in
            guard let self else { return }
            guard covered else {
                BoxPanel.current?.close()
                return self.press(icon, right: right)
            }
            let stale = self.live.first { $0.id == icon.id }?.frame
            self.peeking = app
            var reached = false
            // 保险：1.5 秒还没点到它，就算了
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !reached, self.peeking == app else { return }
                    log.error("没能在幕帘底下打开 \(icon.id, privacy: .public)")
                    self.endPeek()
                }
            }
            self.applyHiding { [weak self] in
                self?.waitUntilShown(icon, app: app, stale: stale, since: Date()) { item in
                    guard let self else { return }
                    reached = true
                    let before = Self.popups(pid: item.pid, bundleID: item.bundleID)
                    MenuBarItems.press(item, right: right)
                    self.readQuietly(item, right: right, before: before, tries: 12, in: view, cell: cell)
                }
            }
        }
    }

    /// 点开以后每 0.04 秒找一次它的菜单，最多找 12 次
    private func readQuietly(_ item: MenuBarIcon, right: Bool, before: Set<CGWindowID>, tries: Int, in view: NSView, cell: NSRect) {
        nonisolated(unsafe) let item = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let app = self.peeking, app == item.bundleID else { return }
                guard let (menu, source) = MenuMirror.readOpened(item) else {
                    if tries > 1 { return self.readQuietly(item, right: right, before: before, tries: tries - 1, in: view, cell: cell) }
                    // 这次弹的不是菜单：让你看到它，照平常那样等它关
                    self.noteDynamic(app, right, false)
                    MenuBarFreeze.shared.liftCurtain()
                    BoxPanel.current?.close()
                    return self.watchPopup(of: item, right: right, before: before)
                }
                log.info("在幕帘底下读到 \(item.id, privacy: .public) 的菜单（\(menu.items.count) 项）")
                MenuMirror.cancel(source)
                self.peeking = nil
                self.applyHiding()
                // 等它的菜单淡出再揭开幕帘；菜单栏那一条多盖一会儿，等图标收回去、旁边的图标靠拢
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    MenuBarFreeze.shared.liftCurtain()
                    MenuBarFreeze.shared.thaw(after: 0.7)
                    // 面板这时已经收起了（你点了别处）就不弹
                    guard view.window?.isVisible == true else { return }
                    if menu.popUp(positioning: nil, at: NSPoint(x: cell.minX, y: cell.maxY + 2), in: view) {
                        BoxPanel.current?.close()
                    }
                }
            }
        }
    }

    private func noteMirrorable(_ app: String) {
        guard !mirrorable.contains(app) else { return }
        mirrorable.insert(app)
        UserDefaults.standard.set(Array(mirrorable), forKey: "stash.mirrorable")
    }

    /// 菜单只能挂在自己图标上的应用（正在运行、从没读到过它的菜单）
    func isOwnMenuOnly(_ icon: KnownIcon) -> Bool {
        let app = StashConfig.app(of: icon.id)
        return StashConfig.canHide(icon.id) && !mirrorable.contains(app)
            && !NSRunningApplication.runningApplications(withBundleIdentifier: app).isEmpty
    }

    /// 辅助功能的坐标（左上角为原点）→ 屏幕坐标（左下角为原点）
    static func cocoa(_ r: CGRect) -> NSRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    /// 日志用：这些窗口属于谁、在哪一层、多大
    private static func describe(_ ids: Set<CGWindowID>) -> String {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter { ids.contains(($0[kCGWindowNumber as String] as? CGWindowID) ?? 0) }.map { w in
            let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return "\(w[kCGWindowOwnerName as String] ?? "?") 层\(w[kCGWindowLayer as String] ?? "?") \(Int(b["Width"] ?? 0))×\(Int(b["Height"] ?? 0))"
        }.joined(separator: "、")
    }

    /// 这个应用现在开着的、看得见的、不在普通窗口层的窗口（菜单、弹出面板）。
    /// 同一家的其他进程也算（Gemini 的菜单由另一个进程画，bundle id 前三段一样）；系统自己一闪而过的高亮窗口不算。
    private static func popups(pid: pid_t, bundleID: String?) -> Set<CGWindowID> {
        let family = (bundleID ?? "").split(separator: ".").prefix(3).joined(separator: ".")
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { w in
            guard let owner = w[kCGWindowOwnerPID as String] as? pid_t, (w[kCGWindowLayer as String] as? Int ?? 0) > 0 else { return nil }
            // 几乎透明的、小小一条的（提示文字之类）不算菜单
            let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            guard (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.5, (b["Width"] ?? 0) > 40, (b["Height"] ?? 0) > 30 else { return nil }
            let mine = owner == pid
                || (!family.isEmpty && NSRunningApplication(processIdentifier: owner)?.bundleIdentifier?.hasPrefix(family) == true)
            return mine ? w[kCGWindowNumber as String] as? CGWindowID : nil
        })
    }

    // MARK: 整理

    /// 整理收纳格就是设置窗口的“收纳”那一页
    func openOrganizer() { SettingsWindow.shared?.show(.stash) }

    func update(_ change: (inout StashConfig) -> Void) {
        guard var c = config else { return }
        change(&c)
        config = c
        save()
        syncBoxItems()
        applyHiding()
    }

    /// 系统按应用藏，所以一个图标换地方，同一个应用的其他图标跟着走
    /// 放进收纳格时 brim 把它吞进来，放回菜单栏时吐出来（应用没在跑、或者隐藏不了时就直接改）。
    func move(_ icon: KnownIcon, to place: StashConfig.Place) {
        let app = StashConfig.app(of: icon.id)
        refreshIcons(capture: false)
        let wasHidden = hiddenApps.contains(app) && !pausedForCall
        let old = config?.place(of: icon.id)
        let item = live.first { $0.bundleID == app }
        // 先改设置，真图标什么时候隐藏 / 显示由动画决定
        let held = holdHiding
        holdHiding = true
        update { c in c.move(app: app, icons: known.map(\.id), to: place) }
        holdHiding = held
        let willHide = hiddenApps.contains(app) && !pausedForCall
        var boxID: String?
        if case .box(let id) = place { boxID = id } else if case .box(let id)? = old { boxID = id }
        guard wasHidden != willHide, let item, hidingProblem == nil, MenuBarRestriction.isAvailable, AppLocation.isInApplications,
              let boxID, let button = boxItems[boxID]?.button, let win = button.window else { return applyHiding() }
        let box = win.convertToScreen(button.convert(button.bounds, to: nil))
        let image = iconImage(for: icon), tint = Self.barTint(button)
        // 放回时它还隐藏着，读到的是旧位置，要估算；放进去时它看得见，位置是准的
        let frame = Self.cocoa(willHide ? item.frame : expectedFrame(of: item))
        if willHide {
            HandoffAnimator.shared.swallow(image: image, tint: tint, target: frame, box: box, hide: { [weak self] in self?.applyHiding() })
        } else {
            HandoffAnimator.shared.spit(image: image, tint: tint, box: box, guess: frame, reveal: { [weak self] in self?.applyHiding() }, actual: {
                MenuBarItems.scan(only: app).first.map { Self.cocoa($0.frame) }
            }, done: { [weak self] in self?.refreshIcons(capture: false) })
        }
    }

    /// 隐藏着的图标显示出来时大概会在哪：读到的是它隐藏前的旧位置（所有图标都显示时的），
    /// 真正会紧贴在它右边最近的那个看得见的图标左边（图标之间隔 6 点）
    private func expectedFrame(of item: MenuBarIcon) -> CGRect {
        let shown = live.filter { $0.id != item.id && !hiddenApps.contains(StashConfig.app(of: $0.id)) && $0.frame.minX > item.frame.minX }
        guard let right = shown.min(by: { $0.frame.minX < $1.frame.minX }) else { return item.frame }
        return CGRect(x: right.frame.minX - 6 - item.frame.width, y: item.frame.minY, width: item.frame.width, height: item.frame.height)
    }

    /// 菜单栏上图标的颜色（跟着菜单栏的深浅）
    private static func barTint(_ button: NSStatusBarButton) -> NSColor {
        var tint = NSColor.white
        button.effectiveAppearance.performAsCurrentDrawingAppearance { tint = NSColor.labelColor.usingColorSpace(.sRGB) ?? .white }
        return tint
    }

    func addBox() {
        let used = Set(boxes.map(\.glyph))
        let glyph = Glyph.options.first { !used.contains($0.id) }?.id ?? "stone"
        update { $0.boxes.append(StashBox(name: L("新收纳格", "New box"), glyph: glyph)) }
    }

    /// 忘掉一个图标（比如应用已经删了）
    func forget(_ icon: KnownIcon) {
        known.removeAll { $0.id == icon.id }
        if let data = try? JSONEncoder().encode(known) { UserDefaults.standard.set(data, forKey: Self.knownKey) }
    }

    private func save() {
        if let config, let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }
}
