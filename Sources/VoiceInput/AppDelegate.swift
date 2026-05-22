import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let transcriber = SpeechTranscriber()
    private let floatingPanel = FloatingPanelController()
    private let injector = TextInjector()
    private let refiner = LLMRefiner(settings: .shared)

    private var fnMonitor: FnKeyMonitor?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var latestTranscript = ""
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureCallbacks()
        requestSpeechAndMicrophonePermissions()
        installFnMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fnMonitor?.stop()
        transcriber.stop()
    }
}

private extension AppDelegate {
    func configureCallbacks() {
        transcriber.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                self?.latestTranscript = text
                self?.floatingPanel.updateText(text.isEmpty ? "Listening..." : text)
                if isFinal {
                    self?.latestTranscript = text
                }
            }
        }

        transcriber.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.floatingPanel.updateAudioLevel(level)
            }
        }

        transcriber.onError = { [weak self] message in
            DispatchQueue.main.async {
                self?.floatingPanel.updateText(message)
            }
        }
    }

    func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
        item.button?.imagePosition = .imageOnly
        item.menu = makeMenu()
        statusItem = item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "Voice Input", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in SpeechLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = settings.language == language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()
        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleLLM(_:)), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = settings.llmEnabled ? .on : .off
        llmMenu.addItem(enabledItem)
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)
        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let permissionsItem = NSMenuItem(title: "Open Privacy Settings...", action: #selector(openPrivacySettings(_:)), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    func refreshMenu() {
        statusItem?.menu = makeMenu()
    }

    func requestSpeechAndMicrophonePermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }

        if #available(macOS 14.0, *) {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func installFnMonitor() {
        fnMonitor = FnKeyMonitor(
            onPress: { [weak self] in
                DispatchQueue.main.async {
                    self?.startRecording()
                }
            },
            onRelease: { [weak self] in
                DispatchQueue.main.async {
                    self?.finishRecording()
                }
            }
        )

        do {
            try fnMonitor?.start()
        } catch {
            floatingPanel.show(text: "Input monitoring permission needed")
            floatingPanel.hide(after: 2.0)
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        latestTranscript = ""
        floatingPanel.show(text: "Listening...")
        transcriber.language = settings.language

        do {
            try transcriber.start()
        } catch {
            floatingPanel.updateText("Speech unavailable")
            floatingPanel.hide(after: 1.6)
            isRecording = false
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        isRecording = false

        let transcript = transcriber.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = transcript.isEmpty ? latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines) : transcript

        guard !candidate.isEmpty else {
            floatingPanel.updateText("No speech detected")
            floatingPanel.hide(after: 0.9)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            var finalText = candidate
            if self.settings.llmEnabled && self.settings.hasCompleteLLMConfiguration {
                await MainActor.run {
                    self.floatingPanel.updateText("Refining...")
                    self.floatingPanel.updateAudioLevel(0.12)
                }
                finalText = (try? await self.refiner.refine(candidate)) ?? candidate
            }

            let textToInject = finalText
            await MainActor.run {
                self.floatingPanel.updateText(textToInject)
            }
            self.injector.inject(textToInject)
            await MainActor.run {
                self.floatingPanel.hide()
            }
        }
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = SpeechLanguage(rawValue: rawValue) else {
            return
        }
        settings.language = language
        refreshMenu()
    }

    @objc func toggleLLM(_ sender: NSMenuItem) {
        settings.llmEnabled.toggle()
        refreshMenu()
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        let controller = settingsWindowController ?? SettingsWindowController(settings: settings, refiner: refiner)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openPrivacySettings(_ sender: NSMenuItem) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
