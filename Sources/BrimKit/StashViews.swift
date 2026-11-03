import AppKit
import BrimCore
import OSLog
import SwiftUI

/// 菜单栏图标在 brim 面板里显示成什么：应用自己的图标；系统那几个用系统符号。
@MainActor
func iconImage(for icon: KnownIcon) -> NSImage {
    // 开了“屏幕录制”、截到过它在菜单栏上的样子，就用那个
    if let real = IconCapture.shared.image(for: icon.id) { return real }
    let systemSymbols: [(match: String, symbol: String)] = [
        ("拼音", "keyboard"), ("输入", "keyboard"), ("Wi", "wifi"), ("电池", "battery.75"), ("Battery", "battery.75"),
        ("蓝牙", "bluetooth"), ("搜索", "magnifyingglass"), ("Siri", "mic"), ("声音", "speaker.wave.2"),
    ]
    if icon.bundleID?.hasPrefix("com.apple.") == true,
       let s = systemSymbols.first(where: { icon.label.contains($0.match) }),
       let img = NSImage(systemSymbolName: s.symbol, accessibilityDescription: nil) {
        return img
    }
    // 应用关掉了也拿得到图标：按应用的身份找到它装在哪
    if let id = icon.bundleID {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.icon { return running }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
    }
    return NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
}

/// 收纳格面板里的图标格：一排排图标，没有名字（名字在鼠标停一下时出现）。外面的玻璃由面板画。
final class IconGridView: NSView {
    private let icons: [KnownIcon]
    /// 第二个参数：是不是右键；后两个：这块图标格和点的那一格（它的菜单从这一格正下方弹出）
    private let onPick: (KnownIcon, Bool, NSView, NSRect) -> Void
    private let columns: Int
    private var hovered: Int?
    static let cell: CGFloat = 36
    static let inset: CGFloat = 8

    @MainActor init(icons: [KnownIcon], onPick: @escaping (KnownIcon, Bool, NSView, NSRect) -> Void) {
        self.icons = icons
        self.onPick = onPick
        columns = min(6, max(1, icons.count))
        let rows = (icons.count + columns - 1) / columns
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(columns) * Self.cell + Self.inset * 2,
                                 height: CGFloat(rows) * Self.cell + 4))
        for (i, icon) in icons.enumerated() {
            let v = NSImageView(image: iconImage(for: icon))
            v.imageScaling = .scaleProportionallyUpOrDown
            v.contentTintColor = .labelColor // 系统符号别显示成灰的
            v.frame = rect(i).insetBy(dx: 7, dy: 7)
            v.toolTip = icon.displayName
            v.setAccessibilityLabel(icon.displayName)
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func rect(_ i: Int) -> NSRect {
        NSRect(x: Self.inset + CGFloat(i % columns) * Self.cell, y: 2 + CGFloat(i / columns) * Self.cell, width: Self.cell, height: Self.cell)
    }

    private func index(at p: NSPoint) -> Int? {
        icons.indices.first { rect($0).contains(p) }
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHover(index(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    private func setHover(_ i: Int?) {
        guard i != hovered else { return }
        hovered = i
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let h = hovered else { return }
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: rect(h).insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8).fill()
    }

    override func mouseUp(with event: NSEvent) { pick(event, right: false) }
    override func rightMouseUp(with event: NSEvent) { pick(event, right: true) }

    private func pick(_ event: NSEvent, right: Bool) {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        onPick(icons[i], right, self, rect(i))
    }
}

/// “整理菜单栏”窗口：上面管收纳格（名字、样子），下面给每个菜单栏图标选放在哪。
struct OrganizerView: View {
    let stash: MenuBarStash

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !stash.trusted {
                permission
            } else if let config = stash.config {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        boxesSection(config)
                        iconsSection(config)
                    }
                    .padding(22)
                }
                Divider()
                footer
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("请先允许 brim 使用“辅助功能”", "Allow brim to use Accessibility")).font(.title3.weight(.semibold))
            Text(L("brim 需要读取菜单栏上有哪些图标，并在你点击收纳格里的图标时替你打开它的菜单，这要用到系统的“辅助功能”权限。", "brim needs to see which icons are in the menu bar and open an icon's menu when you click it in a box. This uses the system's Accessibility permission."))
                .foregroundStyle(.secondary)
            Text(L("点击下面的按钮，brim 会打开对应的设置页并说明怎么做。打开后这里会自动刷新。", "Click the button below. brim opens the right settings page and shows you what to do. This page updates once it's on."))
                .foregroundStyle(.secondary)
            Button(L("前往打开", "Turn On…")) { PermissionGuide.show(.accessibility) }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func boxesSection(_ config: StashConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("收纳格", "Boxes")).font(.headline)
            Text(L("这些收纳格会显示在菜单栏上，点击一个就会弹出放在里面的图标。", "These boxes appear in the menu bar. Click one to see the icons inside.")).font(.callout).foregroundStyle(.secondary)
            ForEach(config.boxes) { box in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(Glyph.options, id: \.id) { g in
                            Button { stash.update { c in c.boxes[c.boxes.firstIndex { $0.id == box.id }!].glyph = g.id } } label: {
                                Label { Text(g.name) } icon: { Image(nsImage: Glyph.image(g.id)) }
                            }
                        }
                    } label: {
                        Image(nsImage: Glyph.image(box.glyph)).renderingMode(.template)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 40)
                    .help(L("更换样式", "Change style"))
                    TextField(L("名称", "Name"), text: Binding(
                        get: { box.name },
                        set: { name in stash.update { c in c.boxes[c.boxes.firstIndex { $0.id == box.id }!].name = name } }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    Text({ let n = config.icons(in: box.id, from: stash.known.map(\.id).filter(StashConfig.canHide)).count; return L("\(n) 个图标", n == 1 ? "1 icon" : "\(n) icons") }())
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(Extensions.boxAccessories.indices, id: \.self) { i in
                        let extra = Extensions.boxAccessories[i]
                        let first = config.boxes.first?.id
                        Toggle(extra.toggleTitle, isOn: Binding(
                            get: { extra.shows(in: box.id, firstBox: first) },
                            set: { extra.setShows($0, in: box.id, firstBox: first) }
                        ))
                        .toggleStyle(.checkbox)
                        .help(extra.toggleHelp)
                    }
                    if config.boxes.count > 1 {
                        Button(L("删除", "Delete")) { stash.update { $0.removeBox(box.id) } }
                            .buttonStyle(.link)
                            .help(L("里面的图标会回到第一个收纳格", "Its icons move back to the first box"))
                    }
                }
            }
            Button(L("+ 新建收纳格", "+ New Box")) { stash.addBox() }
                .buttonStyle(.link)
        }
    }

    private func iconsSection(_ config: StashConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("菜单栏上的图标", "Menu bar icons")).font(.headline)
            Text(L("给每个图标选择位置，立即生效。同一个应用的图标会一起移动；Apple 自带的图标无法隐藏。", "Choose where each icon goes. Changes apply right away. Icons from the same app move together; Apple's own icons can't be hidden.")).font(.callout).foregroundStyle(.secondary)
            Picker(selection: Binding(get: { stash.handoffStyle }, set: { stash.handoffStyle = $0 })) {
                ForEach(HandoffStyle.allCases) { Text($0.title).tag($0) }
            } label: {
                Text(L("打开菜单只能挂在自己图标上的 app 时", "Opening apps whose menu stays on their own icon"))
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help(L("这类 app 的菜单只会从它在菜单栏上的位置弹出。岛：点中的那一格变成一颗黑色胶囊，带着图标升到菜单栏；归位：图标沿一道弧线飞回去。", "These apps only open their menu from their own spot in the menu bar. Island: the cell you click becomes a black capsule that carries the icon up to the menu bar. Return: the icon flies back along an arc."))
            ForEach(stash.known) { icon in
                HStack(spacing: 10) {
                    Image(nsImage: iconImage(for: icon)).resizable().scaledToFit().frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(icon.displayName).lineLimit(1)
                            Text(StashConfig.canHide(icon.id) ? (stash.isHidden(icon) ? L("已隐藏", "Hidden") : L("在菜单栏上", "In menu bar")) : L("系统图标", "System icon"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if stash.isOwnMenuOnly(icon) {
                            Text(L("它的菜单只能从它自己的图标打开，建议留在菜单栏上", "Its menu only opens from its own icon. Best kept in the menu bar."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if stash.isOwnMenuOnly(icon), config.place(of: icon.id) != .visible {
                        Button(L("放回菜单栏", "Keep in Menu Bar")) { stash.move(icon, to: .visible) }
                            .controlSize(.small)
                    }
                    Picker("", selection: Binding(
                        get: { StashConfig.canHide(icon.id) ? tag(config.place(of: icon.id)) : "visible" },
                        set: { v in stash.move(icon, to: v == "visible" ? .visible : .box(v)) }
                    )) {
                        Text(L("显示在菜单栏", "Show in menu bar")).tag("visible")
                        Divider()
                        ForEach(config.boxes) { b in Text(L("放进“\(b.name)”", "Put in “\(b.name)”")).tag(b.id) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                    .disabled(!StashConfig.canHide(icon.id))
                }
                .padding(.vertical, 2)
                .contextMenu { Button(L("忘记这个图标", "Forget this icon")) { stash.forget(icon) } }
            }
        }
    }

    private func tag(_ place: StashConfig.Place) -> String {
        if case .box(let id) = place { return id }
        return "visible"
    }

    /// 藏得怎么样：藏不了就说为什么（不在“应用程序”里时给一个按钮挪过去）
    private func status(_ count: Int) -> String {
        if let problem = stash.hidingProblem { return problem }
        if stash.pausedForCall { return L("正在通话，图标暂时全部显示，结束后自动收起。", "In a call: all icons are showing for now and will be hidden again afterwards.") }
        if count == 0 { return L("目前没有隐藏的应用。", "No apps are hidden.") }
        return L("已隐藏 \(count) 个应用。退出 brim 后它们会自动回到菜单栏。", "\(count) \(count == 1 ? "app" : "apps") hidden. They come back to the menu bar when brim quits.")
    }

    private var footer: some View {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let count = stash.hiddenApps.intersection(running).count
        return HStack(alignment: .center, spacing: 12) {
            Text(status(count))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle(L("通话时暂停", "Pause during calls"), isOn: Binding(get: { stash.pauseInCalls }, set: { stash.pauseInCalls = $0 }))
                .toggleStyle(.checkbox)
                .help(L("摄像头或麦克风在用时，所有图标暂时显示在菜单栏上，系统的通话、摄像头控件也能看到；结束后自动收起", "While the camera or microphone is in use, all icons show in the menu bar so the system's call and camera controls stay visible; they're hidden again afterwards"))
            if stash.hidingProblem != nil, !AppLocation.isInApplications {
                Button(L("移到“应用程序”", "Move to Applications")) { AppLocation.offerMoveIfNeeded() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }
}
