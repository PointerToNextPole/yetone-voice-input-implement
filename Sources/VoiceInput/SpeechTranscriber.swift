import AVFoundation
import Foundation
import Speech

final class SpeechTranscriber {
    var language: SpeechLanguage = .simplifiedChinese
    var onTranscript: ((String, Bool) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onError: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var lastTranscript = ""
    private var envelope: CGFloat = 0

    func start() throws {
        stop()

        lastTranscript = ""
        envelope = 0

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            onError?("Speech permission needed")
            return
        }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))
        guard let recognizer, recognizer.isAvailable else {
            onError?("Recognizer unavailable")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.publishLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                self.onTranscript?(text, result.isFinal)
            }

            if error != nil {
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
            }
        }
    }

    @discardableResult
    func stop() -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.finish()
        recognitionTask = nil

        let text = lastTranscript
        onLevel?(0)
        return text
    }
}

private extension SpeechTranscriber {
    func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
            }
        }

        let mean = sum / Float(frameLength * channelCount)
        let rms = sqrt(max(mean, 0))
        let normalized = CGFloat(min(max(rms * 18, 0), 1))
        let coefficient: CGFloat = normalized > envelope ? 0.40 : 0.15
        envelope = envelope + (normalized - envelope) * coefficient
        onLevel?(envelope)
    }
}
