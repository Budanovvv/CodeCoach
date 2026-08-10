import AppKit
import CoreGraphics

/// Global key capture via CGEventTap. Needs the Accessibility permission, which
/// on macOS already covers listening to the keyboard for an event tap — a
/// separate Input Monitoring grant is not required and only confuses users.
///
/// The tap is listen-only: it observes keys and never swallows them. That is
/// why the interaction is built on one key the user never presses otherwise
/// (right ⌘ by default) rather than on arrow keys or chords — an unswallowed
/// arrow key would move the cursor in the editor underneath at the same time as
/// it drove our panel.
final class HotkeyMonitor {
    /// The capture key. A press means "help me": the controller decides whether
    /// that starts a new problem or advances the current one.
    var keyCode: Int64 = 54
    var onHotkey: (() -> Void)?
    var onEsc: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Guards against auto-repeat on plain keys and against a modifier's flag
    /// being re-reported while it is still physically held.
    private var isDown = false

    @discardableResult
    func start() -> Bool {
        stop()
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Without Accessibility this fails silently — no error, no exception,
            // just no events forever. The caller retries on a timer so the
            // permission is picked up without an app restart.
            Log.d("hotkey: tap creation failed (Accessibility not granted?)")
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.d("hotkey: tap created for keycode \(keyCode)")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDown = false
    }

    /// The tap exists AND the system still delivers to it. Revoking Accessibility
    /// kills delivery with no notification, so a periodic check is the only way
    /// to notice and recreate.
    var isAlive: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap it considers slow. Without re-enabling, the
        // hotkey quietly dies after hours of uptime.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.d("hotkey: tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input") -> re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // Events during the disabled window are lost; a missed release would
            // leave isDown stuck and eat the next press.
            isDown = false
            return
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown, code == 53 {
            DispatchQueue.main.async { [weak self] in self?.onEsc?() }
            return
        }
        guard code == keyCode else { return }

        switch type {
        case .keyDown:
            setDown(true)
        case .keyUp:
            setDown(false)
        case .flagsChanged:
            // Modifiers never produce keyDown/keyUp: held and released are the
            // flag appearing and disappearing, filtered to this keycode's side.
            setDown(Self.isModifierFlagActive(event.flags, keyCode: code))
        default:
            break
        }
    }

    private func setDown(_ now: Bool) {
        guard now != isDown else { return }   // swallows auto-repeat
        isDown = now
        guard now else { return }
        DispatchQueue.main.async { [weak self] in self?.onHotkey?() }
    }

    /// Which physical side of a modifier pair is held.
    ///
    /// The shared masks (.maskAlternate and friends) cover BOTH keys of a pair:
    /// with left and right held together, releasing one leaves the flag set and
    /// the release is lost. The NX_DEVICE* bits in the low word tell the sides
    /// apart. Some external and remapped keyboards set neither bit, so the
    /// shared flag alone stays as the fallback.
    static func isModifierFlagActive(_ flags: CGEventFlags, keyCode: Int64) -> Bool {
        let general: CGEventFlags
        let deviceBit: UInt64
        let siblingBit: UInt64
        switch keyCode {
        case 58: (general, deviceBit, siblingBit) = (.maskAlternate, 0x20, 0x40)   // left ⌥
        case 61: (general, deviceBit, siblingBit) = (.maskAlternate, 0x40, 0x20)   // right ⌥
        case 55: (general, deviceBit, siblingBit) = (.maskCommand, 0x08, 0x10)     // left ⌘
        case 54: (general, deviceBit, siblingBit) = (.maskCommand, 0x10, 0x08)     // right ⌘
        case 56: (general, deviceBit, siblingBit) = (.maskShift, 0x02, 0x04)       // left ⇧
        case 60: (general, deviceBit, siblingBit) = (.maskShift, 0x04, 0x02)       // right ⇧
        case 59: (general, deviceBit, siblingBit) = (.maskControl, 0x01, 0x2000)   // left ⌃
        case 62: (general, deviceBit, siblingBit) = (.maskControl, 0x2000, 0x01)   // right ⌃
        case 63: return flags.contains(.maskSecondaryFn)
        default: return false
        }
        guard flags.contains(general) else { return false }
        let raw = flags.rawValue
        if raw & (deviceBit | siblingBit) == 0 { return true }
        return raw & deviceBit != 0
    }
}
