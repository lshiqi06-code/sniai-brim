import AppKit
import BrimCore
import SwiftUI

/// 刘海整块：收着的时候是刘海加旁边一棵小松，展开后往下长成面板。
struct NotchView: View {
    @Bindable var model: NotchModel
    let onToggle: () -> Void

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        let slot = Theme.slotWidth * model.slotProgress
        let width = model.expanded ? Theme.panelWidth : model.notchSize.width + slot
        let shift = model.expanded ? 0 : (model.side == .right ? slot / 2 : -slot / 2)
        let radius: CGFloat = model.expanded ? 22 : 10
        return VStack(spacing: 0) {
            topRow(slot: slot)
            if model.expanded {
                panelBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: width)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).fill(Theme.notch))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .contextMenu { menu }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.islandSize = $0 }
        .offset(x: shift)
    }

    /// 展开后的内容。没有装扩展（开源版）时只有一句提示。
    @ViewBuilder private var panelBody: some View {
        if let content = Extensions.notch {
            content.panel()
        } else {
            Text(L("安装 sniai yard 后，这里会显示 agent 的状态", "Install sniai yard to see your agents here"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 16)
        }
    }

    /// 和真刘海一样高的那一行。收着时点它展开，展开后再点它收起。
    private func topRow(slot: CGFloat) -> some View {
        HStack(spacing: 0) {
            if model.side == .left { pineSlot(slot) }
            Spacer(minLength: 0)
            if model.side == .right { pineSlot(slot) }
        }
        .frame(height: model.notchSize.height)
        .overlay(alignment: model.side == .right ? .trailing : .leading) {
            if model.expanded {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 20)
                    .help(L("收起（鼠标移开或点击别处也会收起）", "Close (moving the pointer away or clicking elsewhere also closes it)"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    private func pineSlot(_ slot: CGFloat) -> some View {
        PineView(busy: Extensions.notch?.busyCount ?? 0, ask: false, grow: model.grow)
            .frame(width: 28, height: 26)
            .frame(width: slot, height: model.notchSize.height, alignment: .bottom)
            .padding(.bottom, 2)
            .clipped()
            .opacity(model.expanded ? 0 : 1)
    }

    @ViewBuilder private var menu: some View {
        Picker(L("松树位置", "Pine position"), selection: Binding(get: { model.side }, set: { model.side = $0; model.startGrow() })) {
            Text(L("左侧", "Left")).tag(PineSide.left)
            Text(L("右侧", "Right")).tag(PineSide.right)
        }
        Button(L("重播生长动画", "Replay growth animation")) { model.startGrow() }
        Extensions.notch?.menuItems()
        Divider()
        Button(L("设置…", "Settings…")) { SettingsWindow.shared?.show(.notch) }
        Button(L("退出 brim", "Quit brim")) { NSApp.terminate(nil) }
    }
}
