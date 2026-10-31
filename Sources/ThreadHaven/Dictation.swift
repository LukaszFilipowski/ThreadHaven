import AVFoundation
import Observation
import Speech

@MainActor
@Observable
final class Dictation {
    private(set) var isRecording = false
    private(set) var error: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var onText: ((String) -> Void)?

    func toggle(locale: Locale, onText: @escaping (String) -> Void) {
        if isRecording { stop() } else { start(locale: locale, onText: onText) }
    }

    func start(locale: Locale, onText: @escaping (String) -> Void) {
        error = nil
        self.onText = onText
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.error = String(localized: "Speech recognition is not allowed. Enable it in System Settings → Privacy & Security.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.error = String(localized: "Microphone access is not allowed.")
                            return
                        }
                        self.begin(locale: locale)
                    }
                }
            }
        }
    }

    private func begin(locale: Locale) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            error = String(localized: "Speech recognition is unavailable for this language.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        isRecording = true
        task = recognizer.recognitionTask(with: request) { result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                if let text { self.onText?(text) }
                if err != nil || final { self.stop() }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isRecording = false
    }
}
