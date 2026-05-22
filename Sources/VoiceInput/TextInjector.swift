import AppKit
import Carbon.HIToolbox
import Foundation
import CoreFoundation

final class TextInjector {
    func inject(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems
        let previousString = pasteboard.string(forType: .string)
        let previousSource = currentInputSource()
        let asciiSource = currentASCIIInputSource()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if shouldSwitchToASCII(from: previousSource) {
            if let asciiSource {
                TISSelectInputSource(asciiSource)
            }
        }

        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let previousSource {
                TISSelectInputSource(previousSource)
            }

            pasteboard.clearContents()
            if let previousItems {
                pasteboard.writeObjects(previousItems)
            } else if let previousString {
                pasteboard.setString(previousString, forType: .string)
            }
        }
    }
}

private extension TextInjector {
    func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags: CGEventFlags = .maskCommand
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    func currentASCIIInputSource() -> TISInputSource? {
        TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
    }

    func shouldSwitchToASCII(from source: TISInputSource?) -> Bool {
        guard let source else { return false }
        let categoryRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory)
        let capableRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable)
        let category = categoryRef.map { unsafeBitCast($0, to: CFString.self) as String }
        let capable = capableRef.map { CFBooleanGetValue(unsafeBitCast($0, to: CFBoolean.self)) } ?? false
        return category == (kTISCategoryKeyboardInputSource as String) && !capable
    }
}
