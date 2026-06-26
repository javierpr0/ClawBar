import AppKit

// MARK: - Entry / subcommand dispatch

let args = CommandLine.arguments
if args.count >= 2 {
    switch args[1] {
    case "hook":
        Hook.run(event: args.count >= 3 ? args[2] : "")
        exit(0)
    case "install":
        Install.runCLI()
        exit(0)
    case "uninstall":
        Install.uninstall()
        exit(0)
    case "--version", "version":
        print("claude-status-bar \(VERSION)")
        exit(0)
    default:
        break
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no main window
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - Colors

let CLAUDE_ORANGE = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1) // #d97757
let WAIT_YELLOW = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1)

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    var timer: Timer?
    var lastMtime: Date = .distantPast
    var state = AppState(sessions: [:], soundSeq: 0)
    var lastSoundSeq = -1
    var lastSig = ""
    let defaults = UserDefaults.standard

    // soft completion chime (embedded mp3); falls back to a system sound
    lazy var completionSound: NSSound? = {
        if let d = Data(base64Encoded: completionSoundBase64), let s = NSSound(data: d) {
            s.volume = 0.7
            return s
        }
        return NSSound(named: "Glass")
    }()

    // icon assets (MIT, m1ckc3s/claude-status-bar): PNG masks tinted at draw time
    lazy var sparkFrames: [NSImage] = Self.decodePNGs(claudeSparkFramePNGs)
    lazy var crabFrames: [NSImage] = Self.decodePNGs(clawdCrabFramePNGs)
    let logoSet: [NSImage] = Data(base64Encoded: claudeLogoPNG).flatMap(NSImage.init(data:)).map { [$0] } ?? []
    let codeGlyphs = ["✻", "✽", "✶", "✳", "✢"]
    lazy var codeGlyphMasks: [NSImage] = codeGlyphs.map { Self.glyphMask($0) }

    // MARK: settings (UserDefaults)
    var showTimer: Bool {
        get { defaults.object(forKey: "showTimer") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showTimer") }
    }
    var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }
    var animStyle: String {
        get { defaults.string(forKey: "animStyle") ?? "spark" }
        set { defaults.set(newValue, forKey: "animStyle") }
    }
    var iconColor: String {
        get { defaults.string(forKey: "iconColor") ?? "orange" }
        set { defaults.set(newValue, forKey: "iconColor") }
    }
    var pinned: String? {
        get { defaults.string(forKey: "pinnedSession") }
        set { defaults.set(newValue, forKey: "pinnedSession") }
    }
    // nil => adaptive template (system black/white); else brand orange
    var tintColor: NSColor? { iconColor == "orange" ? CLAUDE_ORANGE : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.contentTintColor = nil // we paint the icon ourselves
        menu.delegate = self
        statusItem.menu = menu

        state = Store.load()
        lastSoundSeq = state.soundSeq // don't replay sounds queued before launch
        render()

        let t = Timer(timeInterval: 0.066, repeats: true) { [weak self] _ in self?.tick() } // ~15 fps
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: loop
    func tick() {
        reloadIfChanged()
        render()
    }

    func reloadIfChanged() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Store.stateURL.path),
              let m = attrs[.modificationDate] as? Date else { return }
        if m > lastMtime {
            lastMtime = m
            state = Store.load()
            if state.soundSeq > lastSoundSeq {
                if soundEnabled { completionSound?.play() }
                lastSoundSeq = state.soundSeq
            }
        }
    }

    // Pick the one session the icon follows: pinned, else newest busy, else newest.
    func activeSession() -> Session? {
        if let p = pinned, let s = state.sessions[p] { return s }
        let busy = state.sessions.values
            .filter { $0.status != "idle" }
            .sorted { $0.lastUpdate > $1.lastUpdate }
        if let b = busy.first { return b }
        return state.sessions.values.sorted { $0.lastUpdate > $1.lastUpdate }.first
    }

    // MARK: render menu bar item (image + optional label/timer)
    func render() {
        guard let button = statusItem.button else { return }
        let s = activeSession()
        let status = s?.status ?? "idle"
        let animating = status == "thinking" || status == "tool"

        var label = ""
        switch status {
        case "waiting": label = "Permiso"
        case "tool":    label = s?.label ?? ""
        default:        label = ""
        }
        var text = label
        if showTimer, let s = s, s.turnStart > 0, status != "idle" {
            let el = Int(Date().timeIntervalSince1970 - s.turnStart)
            text += (text.isEmpty ? "" : "  ") + fmt(el)
        }

        // skip redraws when nothing visible changed (idle/waiting between seconds)
        let sig = "\(status)|\(text)|\(animStyle)|\(iconColor)"
        if !animating, sig == lastSig { return }
        lastSig = animating ? "" : sig

        switch status {
        case "waiting": button.image = dotIcon(color: WAIT_YELLOW)
        case "thinking", "tool": button.image = animFrame()
        default: button.image = restingIcon()
        }

        if text.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.imagePosition = .imageLeading
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
            ]
            button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attrs)
        }
    }

    // MARK: icon building (ported from m1ckc3s/claude-status-bar, MIT)

    func animFrame() -> NSImage {
        let now = Date().timeIntervalSince1970
        switch animStyle {
        case "crab":
            let n = max(1, crabFrames.count)
            return crabIcon(frame: Int(now * 12.5) % n) // full color, ignores tint
        case "terminal":
            return codeIcon(color: tintColor, glyph: Int(now * 6) % codeGlyphs.count)
        default: // spark
            let n = max(1, sparkFrames.count)
            return Self.tint(sparkFrames, color: tintColor, frame: Int(now * 9) % n)
        }
    }

    func restingIcon() -> NSImage {
        Self.tint(logoSet.isEmpty ? sparkFrames : logoSet, color: tintColor, frame: 0)
    }

    func dotIcon(color: NSColor) -> NSImage {
        let s: CGFloat = 18, d: CGFloat = 9
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    func crabIcon(frame: Int) -> NSImage {
        guard !crabFrames.isEmpty else { return NSImage(size: NSSize(width: 18, height: 18)) }
        let src = crabFrames[frame % crabFrames.count]
        let rep = src.representations.first
        let pw = CGFloat(rep?.pixelsWide ?? Int(src.size.width))
        let ph = CGFloat(rep?.pixelsHigh ?? Int(src.size.height))
        let h: CGFloat = 18, w = (ph > 0 ? h * (pw / ph) : h)
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        img.isTemplate = false
        return img
    }

    func codeIcon(color: NSColor?, glyph: Int) -> NSImage {
        let s: CGFloat = 18
        guard glyph < codeGlyphMasks.count else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = codeGlyphMasks[glyph]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let r = NSRect(x: 0, y: 0, width: s, height: s)
            if let c = color {
                c.setFill(); r.fill()
                mask.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    static func decodePNGs(_ list: [String]) -> [NSImage] {
        list.compactMap { Data(base64Encoded: $0).flatMap(NSImage.init(data:)) }
    }

    // Paint `color` through a frame mask's alpha so the icon recolors. nil => template.
    static func tint(_ set: [NSImage], color: NSColor?, frame: Int) -> NSImage {
        let s: CGFloat = 18
        guard !set.isEmpty else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = set[frame % set.count]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            if let c = color {
                c.setFill(); rect.fill()
                mask.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    // Rasterize a glyph into a centered 60x60 alpha mask filling ~92%.
    static func glyphMask(_ g: String) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 180), .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: g, attributes: attrs)
        let sz = str.size()
        let big = NSImage(size: sz, flipped: false) { _ in str.draw(at: .zero); return true }
        guard let rep = big.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return NSImage(size: NSSize(width: 60, height: 60))
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh, data = rep.bitmapData!
        var minx = w, miny = h, maxx = -1, maxy = -1
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 20 {
            minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, y); maxy = max(maxy, y)
        } }
        guard maxx >= 0 else { return NSImage(size: NSSize(width: 60, height: 60)) }
        let bw = CGFloat(maxx - minx + 1), bh = CGFloat(maxy - miny + 1)
        let out: CGFloat = 60, fill = out * 0.92
        let scale = fill / max(bw, bh)
        let dw = bw * scale, dh = bh * scale
        let srcRect = NSRect(x: CGFloat(minx), y: CGFloat(h - maxy - 1), width: bw, height: bh)
        return NSImage(size: NSSize(width: out, height: out), flipped: false) { _ in
            big.draw(in: NSRect(x: (out - dw) / 2, y: (out - dh) / 2, width: dw, height: dh),
                     from: srcRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    // MARK: menu (rebuilt each open to reflect live sessions + checkmarks)
    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu() }

    func buildMenu() {
        menu.removeAllItems()

        let header = NSMenuItem(title: headerText(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        addCheck("Mostrar temporizador", checked: showTimer, #selector(toggleTimer))
        addCheck("Sonido al terminar (> 1 min)", checked: soundEnabled, #selector(toggleSound))

        let anim = NSMenuItem(title: "Estilo de animación", action: nil, keyEquivalent: "")
        anim.submenu = radioMenu([("spark", "Spark"), ("terminal", "Terminal"), ("crab", "Crab")],
                                 current: animStyle, action: #selector(setAnim(_:)))
        menu.addItem(anim)

        let color = NSMenuItem(title: "Color del ícono", action: nil, keyEquivalent: "")
        color.submenu = radioMenu([("orange", "Naranja"), ("system", "Sistema")],
                                  current: iconColor, action: #selector(setColor(_:)))
        menu.addItem(color)

        menu.addItem(.separator())
        menu.addItem(sessionsItem())

        menu.addItem(.separator())
        addItem("Reinstalar hooks", #selector(reinstall))
        let about = NSMenuItem(title: "claude-status-bar v\(VERSION)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        menu.addItem(.separator())
        addItem("Salir", #selector(quit), key: "q")
    }

    func sessionsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Sesiones (\(state.sessions.count))", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let auto = NSMenuItem(title: "Automático (más reciente)", action: #selector(pinSession(_:)), keyEquivalent: "")
        auto.target = self
        auto.representedObject = ""
        auto.state = pinned == nil ? .on : .off
        sub.addItem(auto)
        sub.addItem(.separator())

        let sessions = state.sessions.values.sorted { $0.lastUpdate > $1.lastUpdate }
        if sessions.isEmpty {
            let none = NSMenuItem(title: "Sin sesiones activas", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            for s in sessions {
                let proj = URL(fileURLWithPath: s.cwd).lastPathComponent
                let title = "\(dot(s.status)) \(proj) · \(s.client)"
                let it = NSMenuItem(title: title, action: #selector(pinSession(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = s.sessionId
                it.state = pinned == s.sessionId ? .on : .off
                sub.addItem(it)
            }
        }
        item.submenu = sub
        return item
    }

    // MARK: menu helpers
    func addCheck(_ title: String, checked: Bool, _ sel: Selector) {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        it.state = checked ? .on : .off
        menu.addItem(it)
    }

    func addItem(_ title: String, _ sel: Selector, key: String = "") {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        menu.addItem(it)
    }

    func radioMenu(_ options: [(String, String)], current: String, action: Selector) -> NSMenu {
        let sub = NSMenu()
        for (key, label) in options {
            let it = NSMenuItem(title: label, action: action, keyEquivalent: "")
            it.target = self
            it.representedObject = key
            it.state = current == key ? .on : .off
            sub.addItem(it)
        }
        return sub
    }

    func headerText() -> String {
        guard let s = activeSession(), s.status != "idle" else { return "Claude inactivo" }
        let word: String
        switch s.status {
        case "thinking": word = "Pensando"
        case "tool":     word = s.label ?? "Ejecutando"
        case "waiting":  word = "Esperando permiso"
        default:         word = "Activo"
        }
        let proj = URL(fileURLWithPath: s.cwd).lastPathComponent
        var t = "\(word) · \(proj)"
        if s.turnStart > 0 {
            t += " · \(fmt(Int(Date().timeIntervalSince1970 - s.turnStart)))"
        }
        return t
    }

    func dot(_ status: String) -> String {
        switch status {
        case "waiting":          return "🟡"
        case "thinking", "tool": return "🟠"
        default:                 return "⚪️"
        }
    }

    // MARK: actions
    @objc func toggleTimer() { showTimer.toggle(); lastSig = ""; render() }
    @objc func toggleSound() { soundEnabled.toggle() }
    @objc func setAnim(_ i: NSMenuItem) { animStyle = (i.representedObject as? String) ?? "spark"; lastSig = ""; render() }
    @objc func setColor(_ i: NSMenuItem) { iconColor = (i.representedObject as? String) ?? "orange"; lastSig = ""; render() }
    @objc func pinSession(_ i: NSMenuItem) {
        let v = (i.representedObject as? String) ?? ""
        pinned = v.isEmpty ? nil : v
        if !v.isEmpty, let s = state.sessions[v] { focus(s) } // jump to that session's app
        lastSig = ""
        render()
    }

    // Bring the session's owning app (Terminal/iTerm/VS Code/Cursor/Claude) to the front.
    func focus(_ s: Session) {
        let bid = s.bundleId ?? bundleId(forClient: s.client)
        guard let bid, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
        else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    func bundleId(forClient client: String) -> String? {
        switch client {
        case "Terminal": return "com.apple.Terminal"
        case "iTerm":    return "com.googlecode.iterm2"
        case "VS Code":  return "com.microsoft.VSCode"
        case "Cursor":   return "com.todesktop.230313mzl4w4u92"
        case "Claude":   return "com.anthropic.claudefordesktop"
        default:         return nil
        }
    }
    @objc func reinstall() {
        Install.configure(binPath: Install.currentExe())
        let a = NSAlert()
        a.messageText = "Hooks reinstalados"
        a.informativeText = "Reinicia las sesiones de Claude Code abiertas para que tomen los hooks."
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
    @objc func quit() { NSApp.terminate(nil) }
}
