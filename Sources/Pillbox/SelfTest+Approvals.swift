import AppKit
import SwiftUI

extension SelfTest {
    /// The approval endpoint for any agent: the agent name, the request parsing, the title and the answer.
    /// No network: the requests are parsed and answered directly.
    static func agentApprovals() {
        check("approvals: a valid agent name is kept, trimmed", DevAPI.cleanAgent(" Claude Code ") == "Claude Code" && DevAPI.cleanAgent("cursor-2.0_x") == "cursor-2.0_x")
        check("approvals: an empty, too long or odd agent name is refused",
              DevAPI.cleanAgent("") == nil && DevAPI.cleanAgent("   ") == nil && DevAPI.cleanAgent(String(repeating: "a", count: 41)) == nil
              && DevAPI.cleanAgent("a&b") == nil && DevAPI.cleanAgent("a\r\nHost: x") == nil && DevAPI.cleanAgent(String(repeating: "a", count: 40)) != nil)

        let query = "POST /approve?agent=Claude%20Code HTTP/1.1\r\nHost: 127.0.0.1:9998"
        let fromQuery = DevAPI.requestedAgent(head: query, body: [:])
        check("approvals: the agent comes from ?agent= in the request line", fromQuery.ok && fromQuery.agent == "Claude Code", "\(fromQuery)")
        let fromBody = DevAPI.requestedAgent(head: "POST /approve HTTP/1.1", body: ["agent": "codex"])
        check("approvals: the agent can also come from the body", fromBody.ok && fromBody.agent == "codex", "\(fromBody)")
        let none = DevAPI.requestedAgent(head: "POST /approve HTTP/1.1", body: ["tool_name": "Bash"])
        check("approvals: no agent named means Claude Code (nil)", none.ok && none.agent == nil, "\(none)")
        let bad = DevAPI.requestedAgent(head: "POST /approve?agent=a%26b HTTP/1.1", body: [:])
        check("approvals: an invalid agent name is a bad request", !bad.ok && bad.agent == nil, "\(bad)")

        let claude = DevAPI.approvalRequest(["tool_name": "Bash", "tool_input": ["command": "rm -rf ./build"]])
        check("approvals: a Claude Code payload gives the tool and the command", claude.tool == "Bash" && claude.detail == "rm -rf ./build", "\(claude)")
        let edit = DevAPI.approvalRequest(["tool_name": "Edit", "tool_input": ["file_path": "/tmp/a.swift"]])
        check("approvals: a file path is shown when there is no command", edit.detail == "/tmp/a.swift", "\(edit)")
        let generic = DevAPI.approvalRequest(["tool": "shell", "arguments": ["url": "https://example.com"]])
        check("approvals: another agent's payload names its tool and input", generic.tool == "shell" && generic.detail == "https://example.com", "\(generic)")
        let empty = DevAPI.approvalRequest([:])
        check("approvals: a payload without a tool is shown as a tool, with an empty input", empty.tool == "A tool" && empty.detail == "{}", "\(empty)")
        let long = DevAPI.approvalRequest(["tool_name": "Bash", "tool_input": ["command": String(repeating: "x", count: 500)]])
        check("approvals: the detail is cut to 240 characters", long.detail.count == 240)

        let claudeTitle = Approval(tool: "Bash", detail: "ls", respond: { _ in }).title
        check("approvals: the Claude Code title is unchanged", claudeTitle == localized("%@ wants to run", "Bash") && claudeTitle.contains("Bash"), claudeTitle)
        let codexTitle = Approval(tool: "shell", detail: "ls", agent: "Codex", respond: { _ in }).title
        check("approvals: an agent's title names the agent and the tool", codexTitle == localized("%@ wants to run %@", "Codex", "shell") && codexTitle.contains("Codex") && codexTitle.contains("shell"), codexTitle)

        check("approvals: Claude Code gets its hookSpecificOutput, unchanged",
              (DevAPI.approvalAnswer("deny", agent: nil)["hookSpecificOutput"] as? [String: String])?["permissionDecision"] == "deny"
              && (DevAPI.approvalAnswer("allow", agent: nil)["hookSpecificOutput"] as? [String: String])?["permissionDecisionReason"] == "Approved from Pillbox"
              && DevAPI.approvalAnswer("ask", agent: nil).isEmpty)
        let codexAllow = DevAPI.approvalAnswer("allow", agent: "codex")
        check("approvals: a named agent gets decision and reason", codexAllow["decision"] as? String == "allow" && codexAllow["reason"] as? String == "Approved from Pillbox" && codexAllow["hookSpecificOutput"] == nil)
        check("approvals: a named agent's deny and ask", DevAPI.approvalAnswer("deny", agent: "codex")["decision"] as? String == "deny"
              && DevAPI.approvalAnswer("ask", agent: "codex")["decision"] as? String == "ask")

        // The island takes the agent along and answers once.
        let m = NotchModel()
        var decided = ""
        m.requestApproval(tool: "shell", detail: "ls", agent: "Codex", timeout: 60) { decided = $0 }
        check("approvals: the island carries the agent name", m.approval?.agent == "Codex" && m.approval?.title == localized("%@ wants to run %@", "Codex", "shell"))
        m.resolveApproval("deny")
        check("approvals: a named agent's request answers once and clears", decided == "deny" && m.approval == nil)
    }
}
