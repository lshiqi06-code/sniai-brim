import BrimCore
import Testing

@Suite struct HiddenAppsTests {
    let icons = [
        "com.netease.uuremote|", "com.openai.codex|ChatGPT", "com.openai.codex|ChatGPT|1",
        "com.apple.systemuiserver|Siri", "com.apple.TextInputMenuAgent|简体拼音",
    ]

    @Test func starterHidesThirdPartyAppsOnly() {
        #expect(StashConfig.starter.hiddenApps(among: icons) == ["com.netease.uuremote", "com.openai.codex"])
    }

    @Test func appleIconsStayEvenWhenPutInABox() {
        var c = StashConfig.starter
        c.set("com.apple.systemuiserver|Siri", to: .box("main"))
        #expect(!c.hiddenApps(among: icons).contains("com.apple.systemuiserver"))
    }

    @Test func oneIconInABoxHidesTheWholeApp() {
        var c = StashConfig(boxes: StashConfig.starter.boxes, visible: Set(icons))
        #expect(c.hiddenApps(among: icons).isEmpty)
        c.set("com.openai.codex|ChatGPT|1", to: .box("main"))
        #expect(c.hiddenApps(among: icons) == ["com.openai.codex"])
    }

    @Test func movingAnAppClearsAllItsRecords() {
        // 迁移时留下过没认出来的编号（#1、#2）：放回菜单栏以后不能因为它们继续隐藏
        var c = StashConfig(boxes: StashConfig.starter.boxes, visible: [])
        for n in 0..<3 { c.set("com.microsoft.Outlook|#\(n)", to: .box("main")) }
        let known = ["com.microsoft.Outlook|#0"]
        c.move(app: "com.microsoft.Outlook", icons: known, to: .visible)
        #expect(c.hiddenApps(among: known + Array(c.assignment.keys)).isEmpty)
        #expect(c.place(of: known[0]) == .visible)
        c.move(app: "com.microsoft.Outlook", icons: known, to: .box("main"))
        #expect(c.hiddenApps(among: known + Array(c.assignment.keys)) == ["com.microsoft.Outlook"])
    }

    @Test func appIsTheBundlePart() {
        #expect(StashConfig.app(of: "com.openai.codex|ChatGPT|1") == "com.openai.codex")
        #expect(StashConfig.app(of: "com.netease.uuremote|") == "com.netease.uuremote")
    }
}
