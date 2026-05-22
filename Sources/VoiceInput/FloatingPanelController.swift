import AppKit
import Foundation
import QuartzCore

final class FloatingPanelController: NSObject {
    private let panel: NSPanel
    private let contentView = FloatingPanelView()
    private var isVisible = false
    private var hideWorkItem: DispatchWorkItem?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = contentView
        panel.orderOut(nil)
    }

    func show(text: String) {
        hideWorkItem?.cancel()
        updateText(text)
        positionAndAnimateIn()
    }

    func updateText(_ text: String) {
        contentView.update(text: text)
        adjustSize(for: text)
    }

    func updateAudioLevel(_ level: CGFloat) {
        contentView.update(level: level)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.animateOut()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

private extension FloatingPanelController {
    func positionAndAnimateIn() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let safeFrame = screen.visibleFrame
        let width = max(360, min(contentView.targetWidth, 560))
        let originX = safeFrame.midX - width / 2
        let originY = safeFrame.minY + 32
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: 56), display: true)
        panel.alphaValue = 0
        contentView.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            contentView.animator().layer?.transform = CATransform3DIdentity
        }
        isVisible = true
    }

    func adjustSize(for text: String) {
        guard isVisible else { return }
        let width = max(360, min(160 + contentView.textWidth(for: text), 560))
        let newFrame = NSRect(
            x: panel.frame.midX - width / 2,
            y: panel.frame.origin.y,
            width: width,
            height: 56
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func animateOut() {
        guard isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            contentView.animator().layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
            self?.contentView.layer?.transform = CATransform3DIdentity
        }
    }
}

private final class FloatingPanelView: NSView {
    private let effectView = NSVisualEffectView()
    private let waveformView = WaveformView()
    private let textField = NSTextField(labelWithString: "")
    private var currentLevel: CGFloat = 0
    private var currentText = "Listening..."
    var targetWidth: CGFloat = 360

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.masksToBounds = true
        layer?.transform = CATransform3DIdentity

        effectView.material = .hudWindow
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.wantsLayer = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effectView)
        effectView.addSubview(waveformView)
        effectView.addSubview(textField)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            waveformView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            waveformView.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 44),
            waveformView.heightAnchor.constraint(equalToConstant: 32),

            textField.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 14),
            textField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -18),
            textField.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String) {
        currentText = text
        textField.stringValue = text
        targetWidth = 160 + textWidth(for: text)
        needsLayout = true
        needsDisplay = true
    }

    func update(level: CGFloat) {
        currentLevel = level
        waveformView.level = level
    }

    func textWidth(for text: String) -> CGFloat {
        let sample = NSString(string: text.isEmpty ? currentText : text)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textField.font as Any
        ]
        let size = sample.boundingRect(
            with: CGSize(width: 420, height: 20),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        ).size
        return ceil(size.width) + 20
    }
}

private final class WaveformView: NSView {
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var displayLevel: CGFloat = 0
    var level: CGFloat = 0 {
        didSet {
            let blended = displayLevel + (level - displayLevel) * 0.22
            displayLevel = max(0.05, min(blended, 1))
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let barWidth: CGFloat = 4
        let spacing: CGFloat = 4
        let totalWidth = 5 * barWidth + 4 * spacing
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.midY
        let maxHeight: CGFloat = 30
        let minHeight: CGFloat = 4

        for (index, weight) in weights.enumerated() {
            let jitter = 0.96 + CGFloat.random(in: 0...0.08)
            let scaled = minHeight + (maxHeight - minHeight) * displayLevel * weight * jitter
            let x = startX + CGFloat(index) * (barWidth + spacing)
            let rect = CGRect(x: x, y: centerY - scaled / 2, width: barWidth, height: scaled)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.labelColor.withAlphaComponent(0.95).setFill()
            path.fill()
        }
    }
}
