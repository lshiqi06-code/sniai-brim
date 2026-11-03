import Foundation

/// 一个收纳格：菜单栏上露出来的一个小图标，点开是放进去的那些图标。
public struct StashBox: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// 格子的样子，见 Glyph（帽檐、松、石灯笼、鱼……）
    public var glyph: String

    public init(id: String = UUID().uuidString, name: String, glyph: String) {
        self.id = id
        self.name = name
        self.glyph = glyph
    }
}

/// 收纳的全部设置：有哪些格子、每个菜单栏图标放在哪。
public struct StashConfig: Codable, Equatable, Sendable {
    public enum Place: Equatable, Sendable {
        case visible
        case box(String)
    }

    public var boxes: [StashBox]
    /// 一直露在外面的图标
    public var visible: Set<String>
    /// 图标 → 收纳格；没写的放进第一个格子
    public var assignment: [String: String]

    public init(boxes: [StashBox], visible: Set<String>, assignment: [String: String] = [:]) {
        self.boxes = boxes
        self.visible = visible
        self.assignment = assignment
    }

    /// 电池、输入法这类系统图标：用户没动过就露在外面
    public static let systemBundles = ["com.apple.MenuBarAgent", "com.apple.TextInputMenuAgent", "com.apple.controlcenter"]

    /// 第一次打开：一个“收纳”格；系统图标露在外面，其余先放进格子里，等用户自己挑。
    public static let starter = StashConfig(boxes: [StashBox(id: "main", name: L("收纳", "Stash"), glyph: "eave")], visible: [])

    public static func isSystem(_ icon: String) -> Bool {
        systemBundles.contains { icon.hasPrefix($0 + "|") }
    }

    /// 图标 id 是“应用|说明|序号”，前半截就是应用的 bundle id
    public static func app(of icon: String) -> String {
        String(icon.prefix { $0 != "|" })
    }

    /// 苹果自己的图标（Siri、输入法、控制中心那些）藏不了：系统的显示限制只按第三方应用算
    public static func canHide(_ icon: String) -> Bool {
        !app(of: icon).hasPrefix("com.apple.")
    }

    /// 要藏起来的应用。系统按应用藏，同一个应用的图标一起藏、一起露，所以有一个图标放进格子，整个应用就藏起来。
    public func hiddenApps(among icons: [String]) -> Set<String> {
        Set(icons.filter { Self.canHide($0) && place(of: $0) != .visible }.map(Self.app))
    }

    public func place(of icon: String) -> Place {
        if visible.contains(icon) { return .visible }
        if let b = assignment[icon], boxes.contains(where: { $0.id == b }) { return .box(b) }
        if Self.isSystem(icon) { return .visible }
        return boxes.first.map { .box($0.id) } ?? .visible
    }

    public mutating func set(_ icon: String, to place: Place) {
        switch place {
        case .visible:
            visible.insert(icon)
            assignment[icon] = nil
        case .box(let id):
            visible.remove(icon)
            assignment[icon] = id
        }
    }

    /// 换一个应用的位置：它名下所有记录都改（包括还没认出来的图标留下的记录），不然漏掉的记录还会让它继续隐藏
    public mutating func move(app: String, icons: [String], to place: Place) {
        for key in assignment.keys where Self.app(of: key) == app { assignment[key] = nil }
        for key in visible where Self.app(of: key) == app { visible.remove(key) }
        for icon in icons where Self.app(of: icon) == app { set(icon, to: place) }
    }

    /// 删掉一个格子：里面的图标回到第一个格子
    public mutating func removeBox(_ id: String) {
        guard boxes.count > 1 else { return }
        boxes.removeAll { $0.id == id }
        assignment = assignment.filter { $0.value != id }
    }

    public func icons(in box: String, from all: [String]) -> [String] {
        all.filter { place(of: $0) == .box(box) }
    }
}
