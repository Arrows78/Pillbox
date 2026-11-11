import AppKit
import SwiftUI
import ServiceManagement

/// The Integrations pane: Ask about screen, the local developer API and quick actions.
struct SettingsIntegrationsPane: View {
    @State private var apiKey = ""
    @State private var keySaved = Keychain.get(AskModel.keyService) != nil
    @AppStorage(Preferences.prUseGitHub.key) private var prUseGitHub = Preferences.prUseGitHub.defaultValue
    @AppStorage(Preferences.prUseGitLab.key) private var prUseGitLab = Preferences.prUseGitLab.defaultValue
    @AppStorage(Preferences.prGitLabHost.key) private var prGitLabHost = Preferences.prGitLabHost.defaultValue
    @AppStorage(Preferences.devAPI.key) private var devAPI = Preferences.devAPI.defaultValue
    @AppStorage(Preferences.terminalFontSize.key) private var terminalFontSize = Preferences.terminalFontSize.defaultValue
    @AppStorage(Preferences.terminalTheme.key) private var terminalTheme = Preferences.terminalTheme.defaultValue

    /// Stores the typed key. Save and Enter both call it; the field clears and the row says "saved" only when the Keychain accepted the key.
    private func saveKey() {
        guard !apiKey.isEmpty else { return }
        guard Keychain.set(apiKey, AskModel.keyService) else {
            NotchModel.shared.show(Activity(symbol: "exclamationmark.triangle", title: localized("Could not save the key in the Keychain"), tint: .orange))
            return
        }
        keySaved = true; apiKey = ""
    }

    /// A row whose button puts `text()` on the pasteboard and says so.
    private func copyRow(_ title: LocalizedStringKey, text: @escaping () -> String) -> some View {
        SettingsRow(title: title) { CopyButton(text: text) }
    }

    /// A Claude Code hook entry as JSON. JSONSerialization escapes the command, so a quote in the path cannot break the output.
    static func hookJSON(event: String, matcher: String? = nil, command: String, timeout: Int) -> String {
        var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
        if let matcher { entry["matcher"] = matcher }
        let root: [String: Any] = ["hooks": [event: [entry]]]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static let zshHook = """
    # Pillbox: show an island when a command runs longer than 15 s
    autoload -Uz add-zsh-hook
    _pillbox_pre() { _pb_cmd="$1"; _pb_t=$SECONDS }
    _pillbox_post() { local s=$? d=$((SECONDS-${_pb_t:-$SECONDS})); [ -n "$_pb_cmd" ] && [ $d -ge 15 ] && curl -s -m 2 -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H "Authorization: Bearer $(security find-generic-password -s dev.labs.pillbox.devapi -w)" -d "{\\"title\\":\\"Command finished (${d}s)\\",\\"message\\":\\"${_pb_cmd:0:80}\\",\\"symbol\\":\\"terminal.fill\\",\\"duration\\":5}" >/dev/null 2>&1 &!; _pb_cmd= }
    add-zsh-hook preexec _pillbox_pre; add-zsh-hook precmd _pillbox_post
    """

    var body: some View {
        SettingsPage(pane: .integrations) {
            SettingsCard(title: "Pull requests") {
                SettingsToggle("GitHub", "Pull requests through the gh command, which must be installed and logged in.", isOn: $prUseGitHub)
                    .onChange(of: prUseGitHub) { _, _ in PullRequestsService.shared.refresh() }
                SettingsToggle("GitLab", "Merge requests through the glab command, which must be installed and logged in. Both can be on at once.", isOn: $prUseGitLab)
                    .onChange(of: prUseGitLab) { _, _ in PullRequestsService.shared.refresh() }
                if prUseGitLab {
                    SettingsRow(title: "GitLab server", subtitle: "Empty for gitlab.com. For a company server, its host name, for example gitlab.example.com.") {
                        TextField("gitlab.com", text: $prGitLabHost).textFieldStyle(.roundedBorder).frame(width: 180)
                            .onSubmit { PullRequestsService.shared.refresh() }
                    }
                }
            }
            SettingsCard { VStack(alignment: .leading, spacing: 8) { QuickActionsEditor() }.padding(12) }
            SettingsCard(title: "Ask about screen") {
                SettingsRow(title: "Anthropic API key", subtitle: keySaved ? "A key is saved in your Keychain" : "No key saved") {
                    HStack {
                        SecureField("", text: $apiKey).textFieldStyle(.roundedBorder).frame(width: 200)
                            .onSubmit { saveKey() }
                        Button("Save key") { saveKey() }.disabled(apiKey.isEmpty)
                        if keySaved { Button("Remove key") { Keychain.delete(AskModel.keyService); keySaved = false } }
                    }.controlSize(.small)
                }
            }
            SettingsNote("Only the text recognised in the area you pick is sent to Anthropic, never the picture. Needs Screen Recording.")
            SettingsCard(title: "Terminal") {
                SettingsRow(title: "Font size", subtitle: "In points, from 10 to 18. Applies to every terminal session.") {
                    HStack(spacing: 8) {
                        Text(verbatim: "\(terminalFontSize) pt").font(.system(size: 12)).monospacedDigit().foregroundStyle(SettingsStyle.dim)
                        Stepper("", value: $terminalFontSize, in: TerminalLook.fontSizes).labelsHidden()
                    }
                }
                .onChange(of: terminalFontSize) { _, _ in TerminalSessions.lookChanged() }
                SettingsRow(title: "Theme", subtitle: "Colors of every terminal session.") {
                    Picker("", selection: $terminalTheme) {
                        Text("Dark").tag(TerminalTheme.dark.rawValue); Text("Light").tag(TerminalTheme.light.rawValue)
                    }.labelsHidden().frame(width: 170)
                }
                .onChange(of: terminalTheme) { _, _ in TerminalSessions.lookChanged() }
            }
            SettingsCard(title: "Developer API") {
                SettingsToggle("Enable local API", "Scripts and AI apps on this Mac can then reach Pillbox, with a private token.", isOn: $devAPI)
                    .onChange(of: devAPI) { _, _ in DevAPI.shared.apply() }
                if devAPI {
                    SettingsRow(title: "Token", subtitle: "Scripts and hooks read it from the Keychain. Regenerating it breaks the ones that hold the old token.") {
                        Button("Regenerate") { DevAPI.regenerateToken() }.controlSize(.small)
                    }
                    SettingsRow(title: "Address", subtitle: "Reachable from this Mac only.") {
                        Text(verbatim: "127.0.0.1:\(DevAPI.defaultPort)").font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsStyle.dim).textSelection(.enabled)
                    }
                    copyRow("Copy MCP configuration") {
                        MCPServer.configuration(executable: Bundle.main.executablePath ?? "/Applications/Pillbox.app/Contents/MacOS/Pillbox")
                    }
                    copyRow("Copy Claude Code turn-summary hook") {
                        Self.hookJSON(event: "Stop", command: Bundle.main.path(forResource: "claude-stop-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-stop-hook.sh", timeout: 10)
                    }
                    copyRow("Copy Claude Code approval hook") {
                        Self.hookJSON(event: "PreToolUse", matcher: "Bash|Write|Edit", command: Bundle.main.path(forResource: "claude-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/claude-hook.sh", timeout: 130)
                    }
                    copyRow("Copy approval hook for another agent") {
                        Self.hookJSON(event: "PreToolUse", command: "\(Bundle.main.path(forResource: "agent-approval-hook", ofType: "sh") ?? "/path/to/Pillbox/scripts/agent-approval-hook.sh") my-agent", timeout: 130)
                    }
                    SettingsNote("For another agent, replace my-agent with its name, for example codex. The Claude Code entries name no agent.")
                    copyRow("Copy zsh hook for long-running commands") { Self.zshHook }
                    copyRow("Copy example request") {
                        "curl -X POST http://127.0.0.1:\(DevAPI.defaultPort)/notify -H 'Authorization: Bearer \(DevAPI.token)' -d '{\"title\":\"Build done\",\"symbol\":\"hammer.fill\"}'"
                    }
                }
            }
        }
    }
}
