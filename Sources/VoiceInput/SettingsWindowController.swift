import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let refiner: LLMRefiner

    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "Test", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    init(settings: AppSettings, refiner: LLMRefiner) {
        self.settings = settings
        self.refiner = refiner

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Refinement Settings"
        window.center()
        super.init(window: window)
        buildUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        loadSettings()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }
}

private extension SettingsWindowController {
    func buildUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        baseURLField.placeholderString = "https://api.openai.com/v1"
        apiKeyField.placeholderString = "API key"
        modelField.placeholderString = "gpt-4o-mini"

        stack.addArrangedSubview(row(label: "API Base URL", field: baseURLField))
        stack.addArrangedSubview(row(label: "API Key", field: apiKeyField))
        stack.addArrangedSubview(row(label: "Model", field: modelField))

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        stack.addArrangedSubview(statusLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)

        testButton.target = self
        testButton.action = #selector(test(_:))
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(testButton)
        buttonRow.addArrangedSubview(saveButton)
        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    func row(label: String, field: NSTextField) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 108).isActive = true
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        row.addArrangedSubview(labelField)
        row.addArrangedSubview(field)
        return row
    }

    func loadSettings() {
        baseURLField.stringValue = settings.apiBaseURL
        apiKeyField.stringValue = settings.apiKey
        modelField.stringValue = settings.model
        statusLabel.stringValue = ""
    }

    func persistSettings() {
        settings.apiBaseURL = baseURLField.stringValue
        settings.apiKey = apiKeyField.stringValue
        settings.model = modelField.stringValue
    }

    @objc func save(_ sender: NSButton) {
        persistSettings()
        statusLabel.stringValue = "Saved"
    }

    @objc func test(_ sender: NSButton) {
        persistSettings()
        testButton.isEnabled = false
        statusLabel.stringValue = "Testing..."
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.refiner.testConfiguration()
                await MainActor.run {
                    self.statusLabel.stringValue = "Connection OK"
                    self.testButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self.statusLabel.stringValue = error.localizedDescription
                    self.testButton.isEnabled = true
                }
            }
        }
    }
}
