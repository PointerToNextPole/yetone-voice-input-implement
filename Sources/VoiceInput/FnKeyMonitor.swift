import ApplicationServices
import Carbon.HIToolbox
import Foundation

final class FnKeyMonitor {
    enum MonitorError: Error {
        case unableToCreateTap
        case unableToCreateRunLoopSource
    }

    private let onPress: () -> Void
    private let onRelease: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnDown = false
    private let queue = DispatchQueue(label: "VoiceInput.FnKeyMonitor")

    init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    func start() throws {
        let mask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handle(eventType: type, event: event)
            },
            userInfo: refcon
        ) else {
            throw MonitorError.unableToCreateTap
        }

        eventTap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            throw MonitorError.unableToCreateRunLoopSource
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    private func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(kVK_Function) else {
            return Unmanaged.passUnretained(event)
        }
        let fnIsDown = event.flags.contains(.maskSecondaryFn)

        queue.async { [weak self] in
            guard let self else { return }
            switch eventType {
            case .keyDown:
                if !self.isFnDown {
                    self.isFnDown = true
                    self.onPress()
                }
            case .keyUp:
                if self.isFnDown {
                    self.isFnDown = false
                    self.onRelease()
                }
            case .flagsChanged:
                if fnIsDown && !self.isFnDown {
                    self.isFnDown = true
                    self.onPress()
                } else if !fnIsDown && self.isFnDown {
                    self.isFnDown = false
                    self.onRelease()
                }
            default:
                break
            }
        }

        return nil
    }
}
