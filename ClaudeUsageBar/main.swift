import Cocoa
import WidgetKit

// Läuft einen Subprozess über posix_spawn und markiert ihn als "nicht verantwortlich"
// gegenüber TCC (macOS-Berechtigungssystem). Ohne das wird jeder Datei-/Foto-/etc.-Zugriff
// des Subprozesses (z. B. durch die claude-CLI) fälschlich dieser App zugeschrieben, und
// macOS fragt bei jedem Aufruf erneut nach Berechtigungen, die die App selbst nie nutzt.
private typealias DisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32

private func runDisclaimed(_ path: String, _ arguments: [String]) -> String? {
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }

    if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim") {
        let disclaim = unsafeBitCast(sym, to: DisclaimFn.self)
        _ = disclaim(&attr, 1)
    }

    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    let outPipe = Pipe()
    let devNull = open("/dev/null", O_WRONLY)
    posix_spawn_file_actions_adddup2(&fileActions, outPipe.fileHandleForWriting.fileDescriptor, 1)
    posix_spawn_file_actions_adddup2(&fileActions, devNull, 2)

    var argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) }
    argv.append(nil)
    var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
    envp.append(nil)
    defer {
        argv.forEach { if let p = $0 { free(p) } }
        envp.forEach { if let p = $0 { free(p) } }
    }

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, path, &fileActions, &attr, &argv, &envp)
    close(devNull)
    try? outPipe.fileHandleForWriting.close()

    guard rc == 0 else {
        try? outPipe.fileHandleForReading.close()
        return nil
    }

    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return String(data: data, encoding: .utf8)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var settingsWindow: NSWindow?
    var sliderLabel: NSTextField?
    let claudePath = NSHomeDirectory() + "/.local/bin/claude"
    let intervalKey = "refreshIntervalMinutes"
    let intelligentKey = "intelligentUpdate"
    let highUsageThreshold = 80
    let intelligentIntervalMinutes: Double = 5

    var lastSession: Int = 0
    var lastWeek: Int = 0

    var refreshMinutes: Double {
        get {
            let v = UserDefaults.standard.double(forKey: intervalKey)
            return v > 0 ? v : 10
        }
        set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
        }
    }

    var intelligentUpdate: Bool {
        get { UserDefaults.standard.bool(forKey: intelligentKey) }
        set { UserDefaults.standard.set(newValue, forKey: intelligentKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Claude …"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(update), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        update()
    }

    func nextIntervalMinutes() -> Double {
        if intelligentUpdate && (lastSession >= highUsageThreshold || lastWeek >= highUsageThreshold) {
            return min(refreshMinutes, intelligentIntervalMinutes)
        }
        return refreshMinutes
    }

    func scheduleNext() {
        timer?.invalidate()
        let interval = nextIntervalMinutes() * 60
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(update), userInfo: nil, repeats: false)
    }

    @objc func update() {
        DispatchQueue.global(qos: .utility).async {
            let result = self.fetchUsage()
            DispatchQueue.main.async {
                self.statusItem.button?.title = result.text
                self.lastSession = result.session
                self.lastWeek = result.week
                UsageStore.save(session: result.session, week: result.week, hasError: result.hasError)
                WidgetCenter.shared.reloadAllTimelines()
                self.scheduleNext()
            }
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                                   styleMask: [.titled, .closable],
                                   backing: .buffered, defer: false)
            window.title = "Settings"
            window.isReleasedWhenClosed = false
            window.center()

            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))

            let label = NSTextField(labelWithString: "Refresh every \(Int(refreshMinutes)) min")
            label.frame = NSRect(x: 20, y: 115, width: 280, height: 20)
            sliderLabel = label

            let slider = NSSlider(value: refreshMinutes, minValue: 1, maxValue: 60,
                                   target: self, action: #selector(sliderChanged(_:)))
            slider.frame = NSRect(x: 20, y: 85, width: 280, height: 20)
            slider.isContinuous = true

            let minLabel = NSTextField(labelWithString: "1")
            minLabel.frame = NSRect(x: 20, y: 65, width: 30, height: 16)
            minLabel.font = NSFont.systemFont(ofSize: 10)
            minLabel.textColor = .secondaryLabelColor

            let maxLabel = NSTextField(labelWithString: "60")
            maxLabel.frame = NSRect(x: 270, y: 65, width: 30, height: 16)
            maxLabel.font = NSFont.systemFont(ofSize: 10)
            maxLabel.textColor = .secondaryLabelColor
            maxLabel.alignment = .right

            let checkbox = NSButton(checkboxWithTitle: "Smart refresh (every 5 min above 80% usage)",
                                     target: self, action: #selector(intelligentToggled(_:)))
            checkbox.frame = NSRect(x: 18, y: 25, width: 290, height: 30)
            checkbox.state = intelligentUpdate ? .on : .off
            checkbox.font = NSFont.systemFont(ofSize: 11)

            contentView.addSubview(label)
            contentView.addSubview(slider)
            contentView.addSubview(minLabel)
            contentView.addSubview(maxLabel)
            contentView.addSubview(checkbox)
            window.contentView = contentView

            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        let minutes = sender.doubleValue.rounded()
        refreshMinutes = minutes
        sliderLabel?.stringValue = "Refresh every \(Int(minutes)) min"
        scheduleNext()
    }

    @objc func intelligentToggled(_ sender: NSButton) {
        intelligentUpdate = (sender.state == .on)
        scheduleNext()
    }

    func fetchUsage() -> (text: String, session: Int, week: Int, hasError: Bool) {
        guard let output = runDisclaimed(claudePath, ["--print", "/usage"]) else {
            return ("Claude ⚠︎", 0, 0, true)
        }

        func extract(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(output.startIndex..., in: output)
            guard let match = regex.firstMatch(in: output, range: range),
                  let r = Range(match.range(at: 1), in: output) else { return nil }
            return String(output[r])
        }

        let sessionStr = extract("Current session: (\\d+)% used") ?? "?"
        let weekStr = extract("Current week \\(all models\\): (\\d+)% used") ?? "?"
        let sessionInt = Int(sessionStr) ?? 0
        let weekInt = Int(weekStr) ?? 0
        let hasError = (sessionStr == "?" || weekStr == "?")
        let text = "S \(sessionStr)% · W \(weekStr)%"
        return (text, sessionInt, weekInt, hasError)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
