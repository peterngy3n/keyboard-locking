import Cocoa

let holdToUnlockSeconds = 2.0

// NX_SYSDEFINED: media, brightness and volume keys.
let systemDefinedEventType: UInt64 = 14

var eventTap: CFMachPort?

/// Swallows every keyboard event while the tap is active.
func keyboardTapCallback(proxy: CGEventTapProxy,
                         type: CGEventType,
                         event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // macOS disables a tap whose callback is too slow; turn it back on so the lock holds.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    return nil
}

/// A button that fires only after the mouse is held down for `holdToUnlockSeconds`,
/// so wiping across the trackpad does not unlock by accident.
final class HoldButton: NSView {

    var onComplete: (() -> Void)?

    private var progress: CGFloat = 0
    private var holdStart: Date?
    private var timer: Timer?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        holdStart = Date()
        let holdTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
        RunLoop.main.add(holdTimer, forMode: .common)
        timer = holdTimer
    }

    override func mouseUp(with event: NSEvent) {
        resetHold()
    }

    private func updateProgress() {
        guard let start = holdStart else {
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        progress = CGFloat(min(elapsed / holdToUnlockSeconds, 1.0))
        needsDisplay = true
        if progress >= 1.0 {
            resetHold()
            onComplete?()
        }
    }

    private func resetHold() {
        timer?.invalidate()
        timer = nil
        holdStart = nil
        progress = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        background.fill()

        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        let filled = NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height)
        NSColor.controlAccentColor.setFill()
        filled.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()

        let title = "Hold to unlock"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        title.draw(at: origin, withAttributes: attributes)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private var headlineLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var lockButton: NSButton!
    private var settingsButton: NSButton!
    private var holdButton: HoldButton!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        if isAccessibilityGranted() {
            showUnlockedState()
        } else {
            showPermissionState()
            waitForPermission()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func waitForPermission() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else {
                return
            }
            self?.permissionTimer?.invalidate()
            self?.permissionTimer = nil
            self?.showUnlockedState()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func showPermissionState() {
        headlineLabel.stringValue = "Permission needed"
        statusLabel.stringValue = "Allow KeyboardLock in Accessibility settings."
        settingsButton.isHidden = false
        lockButton.isHidden = true
        holdButton.isHidden = true
    }

    @objc private func lockKeyboard() {
        guard startKeyboardTap() else {
            showErrorAndQuit(title: "Could not lock the keyboard",
                             message: "macOS refused to create the keyboard event tap. Try removing and re-adding KeyboardLock in the Accessibility list.")
            return
        }
        showLockedState()
    }

    private func unlockKeyboard() {
        stopKeyboardTap()
        showUnlockedState()
    }

    private func showUnlockedState() {
        headlineLabel.stringValue = "Keyboard unlocked"
        statusLabel.stringValue = "Click Lock, then wipe away."
        settingsButton.isHidden = true
        lockButton.isHidden = false
        holdButton.isHidden = true
    }

    private func showLockedState() {
        headlineLabel.stringValue = "Keyboard locked"
        statusLabel.stringValue = "Hold the button below to unlock."
        settingsButton.isHidden = true
        lockButton.isHidden = true
        holdButton.isHidden = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopKeyboardTap()
    }

    private func isAccessibilityGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func startKeyboardTap() -> Bool {
        var mask: UInt64 = 0
        mask |= 1 << UInt64(CGEventType.keyDown.rawValue)
        mask |= 1 << UInt64(CGEventType.keyUp.rawValue)
        mask |= 1 << UInt64(CGEventType.flagsChanged.rawValue)
        mask |= 1 << systemDefinedEventType

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: keyboardTapCallback,
                                          userInfo: nil) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        return true
    }

    private func stopKeyboardTap() {
        guard let tap = eventTap else {
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        eventTap = nil
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "KeyboardLock"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let content = NSView(frame: window.contentRect(forFrameRect: window.frame))

        headlineLabel = NSTextField(labelWithString: "")
        headlineLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        headlineLabel.alignment = .center
        headlineLabel.frame = NSRect(x: 20, y: 160, width: 320, height: 30)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.frame = NSRect(x: 20, y: 128, width: 320, height: 20)

        lockButton = NSButton(title: "Lock keyboard", target: self, action: #selector(lockKeyboard))
        lockButton.bezelStyle = .rounded
        lockButton.controlSize = .large
        lockButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        lockButton.frame = NSRect(x: 60, y: 50, width: 240, height: 52)

        settingsButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .large
        settingsButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        settingsButton.frame = NSRect(x: 40, y: 50, width: 280, height: 52)

        holdButton = HoldButton(frame: NSRect(x: 60, y: 50, width: 240, height: 52))
        holdButton.onComplete = { [weak self] in
            self?.unlockKeyboard()
        }

        content.addSubview(headlineLabel)
        content.addSubview(statusLabel)
        content.addSubview(lockButton)
        content.addSubview(settingsButton)
        content.addSubview(holdButton)
        window.contentView = content

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showErrorAndQuit(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
