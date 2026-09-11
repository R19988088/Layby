import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "tray.2.fill").font(.system(size: 26, weight: .light))
                    .foregroundStyle(.teal).frame(width: 52, height: 52)
                    .glassEffect(.regular.tint(.teal.opacity(0.12)), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("让文件顺路停靠").font(.system(size: 21, weight: .semibold))
                    Text("选择习惯的方式，随时唤出 Layby。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(24)
            Form {
                Section("拖拽时呼出") {
                    Toggle("摇晃文件", isOn: $settings.shakeEnabled)
                    Picker("摇晃幅度", selection: $settings.sensitivity) {
                        ForEach(ShakeSensitivity.allCases) { Text($0.title).tag($0) }
                    }.disabled(!settings.shakeEnabled)
                    Toggle("按住修饰键并拖拽", isOn: $settings.modifierEnabled)
                    Picker("修饰键", selection: $settings.modifier) {
                        ForEach(DragModifier.allCases) { Text($0.title).tag($0) }
                    }.disabled(!settings.modifierEnabled)
                    Toggle("拖到刘海区域", isOn: $settings.notchEnabled)
                    Toggle("无刘海时使用屏幕顶部中央", isOn: $settings.topEdgeEnabled)
                    Text("先按住修饰键再拖拽，或拖拽途中按住，都可以呼出。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("全局快捷键") {
                    Toggle("启用快捷键", isOn: $settings.hotKeyEnabled)
                    HStack {
                        Text("显示停放区")
                        Spacer()
                        ShortcutRecorder(shortcut: settings.shortcut) { shortcut in coordinator.changeShortcut(shortcut) }
                            .frame(width: 160, height: 28).disabled(!settings.hotKeyEnabled)
                    }
                    if let message = coordinator.hotKeyMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                    Text("点击键位后按下新组合键，Esc 取消。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("兼容性") {
                    LabeledContent("已识别的拖拽", value: "\(coordinator.observation.observedDragCount) 次")
                    LabeledContent("辅助功能访问", value: coordinator.observation.hasAccessibilityTrust ? "已允许" : "未允许")
                    Text("鼠标检测无需读取文件内容。若其他应用中摇晃无响应，可在系统设置中允许辅助功能访问；快捷键和手动投放仍可使用。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("打开辅助功能设置") { coordinator.openAccessibilitySettings() }
                        Button("重新检查") { coordinator.refreshObservation() }
                    }
                    TextField("排除应用的 Bundle ID，每行一个", text: $settings.excludedBundleIDs, axis: .vertical)
                        .lineLimit(2...3).font(.system(.caption, design: .monospaced))
                    Text("排除应用仅关闭摇晃和修饰键呼出。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("关闭停放区会清空全部内容，下次打开为空。原文件不会删除；应用接收的临时副本会在使用结束后清理。拖出默认为复制。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480, height: 720)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: HotKeyShortcut
    let onChange: (HotKeyShortcut) -> Void
    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.bezelStyle = .rounded
        button.onChange = onChange
        return button
    }
    func updateNSView(_ button: ShortcutButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = onChange
        if !button.recording { button.title = shortcut.label }
    }
}

@MainActor
private final class ShortcutButton: NSButton {
    var shortcut = HotKeyShortcut.standard
    var onChange: ((HotKeyShortcut) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true
        title = "按下组合键…"
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        if !recording { recording = true; title = "按下组合键…"; return }
        if event.keyCode == 53 { finish(); return }
        let flags = HotKeyShortcut.carbonFlags(event.modifierFlags)
        guard flags != 0, let character = event.charactersIgnoringModifiers, !character.isEmpty else {
            title = "请包含修饰键"; return
        }
        let label = event.keyCode == 49 ? "空格" : character.uppercased()
        onChange?(HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: flags, keyLabel: label))
        finish()
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    private func finish() { recording = false; title = shortcut.label }
}
