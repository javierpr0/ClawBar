import Foundation
import Darwin

let VERSION = "1.0.0"

// MARK: - State model

struct Session: Codable {
    var sessionId: String
    var cwd: String
    var client: String
    var bundleId: String?    // owning app's bundle id, for focusing the session
    var status: String      // idle | thinking | tool | waiting
    var tool: String?
    var label: String?
    var turnStart: Double    // epoch seconds; 0 when idle
    var lastUpdate: Double
    var lastTurnDuration: Double
}

struct AppState: Codable {
    var sessions: [String: Session]
    var soundSeq: Int
}

// MARK: - Store (state.json + flock)

enum Store {
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude-status-bar")
    }
    static var stateURL: URL { dir.appendingPathComponent("state.json") }
    static var lockURL: URL { dir.appendingPathComponent("state.lock") }

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func load() -> AppState {
        guard let data = try? Data(contentsOf: stateURL),
              let st = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState(sessions: [:], soundSeq: 0)
        }
        return st
    }

    static func save(_ st: AppState) {
        ensureDir()
        guard let data = try? JSONEncoder().encode(st) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // Cross-process read-modify-write. flock prevents two concurrent hooks losing a write.
    static func withLock(_ body: (inout AppState) -> Void) {
        ensureDir()
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var st = load()
        body(&st)
        save(st)
    }
}

// MARK: - Tool -> short Spanish label

func labelFor(_ tool: String?) -> String {
    guard let t = tool else { return "" }
    if t.hasPrefix("mcp__") { return "MCP" }
    switch t {
    case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editando"
    case "Read", "NotebookRead":                        return "Leyendo"
    case "Bash", "BashOutput", "KillShell", "KillBash": return "Ejecutando"
    case "Grep", "Glob", "LS":                          return "Buscando"
    case "WebFetch", "WebSearch":                       return "Navegando"
    case "Task", "Agent":                               return "Agente"
    case "TodoWrite":                                   return "Planeando"
    default:                                            return t
    }
}

func detectClient() -> String {
    let env = ProcessInfo.processInfo.environment
    if let b = env["__CFBundleIdentifier"]?.lowercased() {
        if b.contains("cursor") || b.contains("todesktop") { return "Cursor" }
        if b.contains("claude")                            { return "Claude" }
        if b.contains("vscode") || b.contains("code")      { return "VS Code" }
        if b.contains("iterm")                             { return "iTerm" }
        if b.contains("terminal")                          { return "Terminal" }
    }
    switch env["TERM_PROGRAM"] ?? "" {
    case "Apple_Terminal": return "Terminal"
    case "iTerm.app":      return "iTerm"
    case "vscode":         return "VS Code"
    case let other where !other.isEmpty: return other
    default:               return "CLI"
    }
}

func fmt(_ secs: Int) -> String {
    let s = max(0, secs)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Hook subcommand

enum Hook {
    static func run(event: String) {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let sid = (j["session_id"] as? String) ?? "default"
        let cwd = (j["cwd"] as? String) ?? FileManager.default.currentDirectoryPath
        let toolName = j["tool_name"] as? String
        let notifType = j["notification_type"] as? String
        let client = detectClient()
        let bundleId = ProcessInfo.processInfo.environment["__CFBundleIdentifier"]
        let now = Date().timeIntervalSince1970

        Store.withLock { state in
            if event == "SessionEnd" {
                state.sessions[sid] = nil
            } else {
                var s = state.sessions[sid] ?? Session(
                    sessionId: sid, cwd: cwd, client: client, bundleId: bundleId, status: "idle",
                    tool: nil, label: nil, turnStart: 0, lastUpdate: now, lastTurnDuration: 0)
                s.cwd = cwd
                s.client = client
                if let bundleId = bundleId { s.bundleId = bundleId }
                s.lastUpdate = now

                switch event {
                case "SessionStart":
                    s.status = "idle"; s.turnStart = 0; s.tool = nil; s.label = nil
                case "UserPromptSubmit":
                    s.status = "thinking"; s.turnStart = now; s.tool = nil; s.label = nil
                case "PreToolUse":
                    s.status = "tool"; s.tool = toolName; s.label = labelFor(toolName)
                    if s.turnStart == 0 { s.turnStart = now }
                case "PostToolUse", "PostToolUseFailure", "PostToolBatch":
                    s.status = "thinking"; s.tool = nil; s.label = nil
                    if s.turnStart == 0 { s.turnStart = now }
                case "Notification":
                    if notifType == "idle_prompt" {
                        // agent went idle waiting for a prompt -> not a permission gate
                        s.status = "idle"; s.turnStart = 0; s.tool = nil; s.label = nil
                    } else {
                        // permission_prompt / elicitation_* -> waiting on the human
                        s.status = "waiting"
                        if s.turnStart == 0 { s.turnStart = now }
                    }
                case "Stop":
                    if s.turnStart > 0 {
                        let dur = now - s.turnStart
                        s.lastTurnDuration = dur
                        if dur > 60 { state.soundSeq += 1 }
                    }
                    s.status = "idle"; s.turnStart = 0; s.tool = nil; s.label = nil
                default:
                    break
                }
                state.sessions[sid] = s
            }
            // prune sessions untouched for 6h (covers terminals killed without SessionEnd)
            let cutoff = now - 6 * 3600
            state.sessions = state.sessions.filter { $0.value.lastUpdate > cutoff }
        }
    }
}

// MARK: - Install / update

enum Install {
    static var binDest: URL { Store.dir.appendingPathComponent("bin/claude-status-bar") }
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }
    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.claudestatusbar.agent.plist")
    }

    static func currentExe() -> String {
        let p = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: p).resolvingSymlinksInPath().path
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // Full install from any invocation path: copy binary to a stable home, wire hooks + launch agent.
    static func runCLI() {
        let src = currentExe()
        let dest = binDest.path
        try? FileManager.default.createDirectory(
            at: binDest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if src != dest {
            try? FileManager.default.removeItem(atPath: dest) // unlink: safe even if running
            try? FileManager.default.copyItem(atPath: src, toPath: dest)
            chmod(dest, 0o755)
        }
        configure(binPath: dest)
        print("""
        claude-status-bar \(VERSION) instalado.
          binario:  \(dest)
          hooks:    \(settingsURL.path)
          autostart:\(launchAgentURL.path)
        La barra de menús ya debería estar activa. Reinicia sesiones de Claude Code
        abiertas para que tomen los hooks nuevos.
        """)
    }

    // Idempotent: (re)write hooks + launch agent for a given binary path.
    static func configure(binPath: String) {
        writeHooks(binPath: binPath)
        writeLaunchAgent(binPath: binPath)
    }

    static func writeHooks(binPath: String) {
        let events: [(String, String?)] = [
            ("SessionStart", nil),
            ("UserPromptSubmit", nil),
            ("PreToolUse", "*"),
            ("PostToolUse", "*"),
            ("Notification", "*"),
            ("Stop", nil),
            ("SessionEnd", nil),
        ]
        try? FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var root = (try? JSONSerialization.jsonObject(with: (try? Data(contentsOf: settingsURL)) ?? Data()))
            as? [String: Any] ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let marker = "\(quoted(binPath)) hook"

        for (event, matcher) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            // drop our previous groups so re-install never duplicates
            groups = groups.filter { g in
                let hs = g["hooks"] as? [[String: Any]] ?? []
                return !hs.contains { ($0["command"] as? String)?.contains("claude-status-bar") ?? false }
            }
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": "\(marker) \(event)",
                    "async": true,
                ]]
            ]
            if let m = matcher { group["matcher"] = m }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks

        if let out = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? out.write(to: settingsURL, options: .atomic)
        }
    }

    static func writeLaunchAgent(binPath: String) {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>com.claudestatusbar.agent</string>
          <key>ProgramArguments</key>
          <array><string>\(binPath)</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
        // reload so the agent picks up a new binary / restarts cleanly
        run("/bin/launchctl", ["unload", launchAgentURL.path])
        run("/bin/launchctl", ["load", launchAgentURL.path])
    }

    static func uninstall() {
        run("/bin/launchctl", ["unload", launchAgentURL.path])
        try? FileManager.default.removeItem(at: launchAgentURL)
        // strip our hook groups
        if var root = (try? JSONSerialization.jsonObject(with: (try? Data(contentsOf: settingsURL)) ?? Data()))
            as? [String: Any], var hooks = root["hooks"] as? [String: Any] {
            for event in hooks.keys {
                if var groups = hooks[event] as? [[String: Any]] {
                    groups = groups.filter { g in
                        let hs = g["hooks"] as? [[String: Any]] ?? []
                        return !hs.contains { ($0["command"] as? String)?.contains("claude-status-bar") ?? false }
                    }
                    hooks[event] = groups.isEmpty ? nil : groups
                }
            }
            root["hooks"] = hooks
            if let out = try? JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
                try? out.write(to: settingsURL, options: .atomic)
            }
        }
        print("claude-status-bar desinstalado (hooks y autostart removidos).")
    }

    static func quoted(_ path: String) -> String {
        return "\"\(path)\""
    }
}
