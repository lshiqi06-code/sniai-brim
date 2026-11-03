import AppKit
import BrimCore

/// 菜单栏显示限制只认得装在“应用程序”文件夹里的 brim：从别处打开时，系统认不出帽檐是谁的，会把它一起藏掉。
@MainActor
enum AppLocation {
    static var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    /// 不在“应用程序”里就问一次要不要挪过去：拷一份过去、从那里重新打开，再退出这一份
    static func offerMoveIfNeeded() {
        guard !isInApplications, MenuBarRestriction.isAvailable else { return }
        let alert = NSAlert()
        alert.messageText = L("把 brim 移到“应用程序”文件夹？", "Move brim to the Applications folder?")
        alert.informativeText = L("brim 需要安装在“应用程序”文件夹中才能隐藏菜单栏图标。", "brim needs to be in the Applications folder to hide menu bar icons.")
        alert.addButton(withTitle: L("移到“应用程序”", "Move to Applications"))
        alert.addButton(withTitle: L("以后再说", "Not now"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let dest = URL(fileURLWithPath: "/Applications/Brim.app")
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.trashItem(at: dest, resultingItemURL: nil) }
            try FileManager.default.copyItem(at: Bundle.main.bundleURL, to: dest)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
