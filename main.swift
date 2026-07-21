import Cocoa

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
        menu.addItem(NSMenuItem(title: "Jetzt aktualisieren", action: #selector(update), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Einstellungen…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Beenden", action: #selector(quit), keyEquivalent: "q"))
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
            window.title = "Einstellungen"
            window.isReleasedWhenClosed = false
            window.center()

            let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))

            let label = NSTextField(labelWithString: "Aktualisierung alle \(Int(refreshMinutes)) Min.")
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

            let checkbox = NSButton(checkboxWithTitle: "Intelligent aktualisieren (ab 80% Nutzung alle 5 Min.)",
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
        sliderLabel?.stringValue = "Aktualisierung alle \(Int(minutes)) Min."
        scheduleNext()
    }

    @objc func intelligentToggled(_ sender: NSButton) {
        intelligentUpdate = (sender.state == .on)
        scheduleNext()
    }

    func fetchUsage() -> (text: String, session: Int, week: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: claudePath)
        task.arguments = ["--print", "/usage"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ("Claude ⚠︎", 0, 0)
        }
        task.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return ("Claude ⚠︎", 0, 0) }

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
        let text = "S \(sessionStr)% · W \(weekStr)%"
        return (text, sessionInt, weekInt)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
