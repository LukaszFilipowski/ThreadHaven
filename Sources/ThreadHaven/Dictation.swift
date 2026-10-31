import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class Dictation {
    private(set) var isRecording = false
    private(set) var error: String?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onText: ((String) -> Void)?

    func start(locale: Locale, onText: @escaping (String) -> Void) {
        stop()
        error = nil
        self.onText = onText
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = String(localized: "Speech recognition is not allowed. Enable it in System Settings → Privacy & Security.")
                    return
                }
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    self.error = String(localized: "Microphone access is not allowed.")
                    return
                }
                self.begin(locale: locale)
            }
        }
    }

    func stop() {
        onText = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isRecording = false
    }

    private func begin(locale: Locale) {
        guard onText != nil else { return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = String(localized: "Speech recognition is unavailable for this language.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        let engine = AVAudioEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.error = error.localizedDescription
            return
        }

        self.engine = engine
        self.request = request
        isRecording = true
        var current: SFSpeechRecognitionTask?
        current = recognizer.recognitionTask(with: request) { result, failure in
            let text = result?.bestTranscription.formattedString
            let done = failure != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let current, self.task === current else { return }
                if let text { self.onText?(text) }
                if done { self.stop() }
            }
        }
        task = current
    }
}
