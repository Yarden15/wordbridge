import AVFoundation
import AppKit
import CoreAudio
import Speech

/// Listens to one audio source and transcribes it on this Mac:
/// - the sound a meeting app plays (the other people in the call), through a Core Audio process tap;
/// - or your microphone (what you say).
/// English uses `SpeechTranscriber`; languages it doesn't cover (Hebrew) use `DictationTranscriber`.
@available(macOS 26, *)
@MainActor
final class MeetingListener {
    enum Input {
        /// nil captures all sound on the Mac.
        case app(MeetingApp?)
        case microphone
    }

    enum Event: Sendable {
        case status(String)
        /// Text still being recognized; replaced by the next partial or final result.
        case partial(String)
        case final(String)
        case failed(String)
    }

    private let input: Input
    private let language: AppLanguage
    private let onEvent: (Event) -> Void
    private var capture: AudioCapture?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var stopped = false

    init(input: Input, language: AppLanguage, onEvent: @escaping (Event) -> Void) {
        self.input = input
        self.language = language
        self.onEvent = onEvent
    }

    func start() async {
        do {
            let module = try await makeModule()

            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                onEvent(.status("Downloading \(language.englishName) speech recognition (one time)…"))
                try await request.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                throw ListenerError.unavailable
            }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(200))
            inputContinuation = continuation

            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)

            let yield: @Sendable (AnalyzerInput) -> Void = { continuation.yield($0) }
            let capture: AudioCapture
            switch input {
            case .app(let app):
                capture = AudioTapCapture(processes: app.map(AudioProcesses.objects(for:)) ?? [], targetFormat: format, onInput: yield)
            case .microphone:
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw ListenerError.noMicrophoneAccess }
                capture = MicrophoneCapture(targetFormat: format, onInput: yield)
            }
            // Starting can wait on a permission dialog: keep the app responsive meanwhile.
            try await Task.detached { try capture.start() }.value
            guard !stopped else { capture.stop(); return }
            self.capture = capture
            switch input {
            case .app(let app): onEvent(.status(app.map { "Listening to \($0.name)" } ?? "Listening to all sound on this Mac"))
            case .microphone: onEvent(.status("Listening to your microphone"))
            }
        } catch {
            stop()
            onEvent(.failed(error.localizedDescription))
        }
    }

    /// The recognizer for the language, wired to report its results.
    private func makeModule() async throws -> any SpeechModule {
        let locale = language.speechLocale
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = SpeechTranscriber(
                locale: supported, transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
            report(transcriber.results.map { ($0.text, $0.isFinal) })
            return transcriber
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let transcriber = DictationTranscriber(
                locale: supported, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
            report(transcriber.results.map { ($0.text, $0.isFinal) })
            return transcriber
        }
        throw ListenerError.unsupportedLanguage(language)
    }

    private func report<S: AsyncSequence & Sendable>(_ results: S) where S.Element == (AttributedString, Bool) {
        resultsTask = Task { [weak self] in
            do {
                for try await (attributed, isFinal) in results {
                    let text = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let self else { return }
                    if isFinal {
                        if !text.isEmpty { self.onEvent(.final(text)) }
                        self.onEvent(.partial(""))
                    } else {
                        self.onEvent(.partial(text))
                    }
                }
            } catch {
                self?.onEvent(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        stopped = true
        capture?.stop()
        capture = nil
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }

    enum ListenerError: LocalizedError {
        case unavailable, unsupportedLanguage(AppLanguage), noMicrophoneAccess
        var errorDescription: String? {
            switch self {
            case .unavailable: "Speech recognition isn't available on this Mac."
            case .unsupportedLanguage(let language): "Speech recognition doesn't support \(language.englishName) on this Mac."
            case .noMicrophoneAccess:
                "Wordbridge can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone."
            }
        }
    }
}

protocol AudioCapture: AnyObject, Sendable {
    func start() throws
    func stop()
}

/// Your microphone, converted to the recognizer's format.
@available(macOS 26, *)
final class MicrophoneCapture: AudioCapture, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private let onInput: @Sendable (AnalyzerInput) -> Void

    init(targetFormat: AVAudioFormat, onInput: @escaping @Sendable (AnalyzerInput) -> Void) {
        self.targetFormat = targetFormat
        self.onInput = onInput
    }

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw MeetingListener.ListenerError.noMicrophoneAccess
        }
        let target = targetFormat
        let onInput = onInput
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if let converted = AudioConversion.convert(buffer, with: converter, to: target) {
                onInput(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

enum AudioConversion {
    static func convert(_ source: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0 else { return nil }
        let ratio = format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

// MARK: - Finding the meeting app's audio

enum AudioProcesses {
    /// Core Audio's process objects that belong to the app (including its helpers,
    /// e.g. Chrome plays sound from "Google Chrome Helper").
    static func objects(for app: MeetingApp) -> [AudioObjectID] {
        allProcessObjects().filter { object in
            guard let bundleID = bundleID(of: object) else { return false }
            return app.audioBundlePrefixes.contains { bundleID.hasPrefix($0) }
        }
    }

    private static func allProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return objects
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

// MARK: - Process tap

/// Taps the output of some processes (or of the whole Mac) without muting it, through a private
/// aggregate device, and hands the audio over converted to `targetFormat`.
@available(macOS 26, *)
final class AudioTapCapture: AudioCapture, @unchecked Sendable {
    private let processes: [AudioObjectID]
    private let targetFormat: AVAudioFormat
    private let onInput: @Sendable (AnalyzerInput) -> Void
    private let queue = DispatchQueue(label: "io.github.wordbridge.audio-tap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init(processes: [AudioObjectID], targetFormat: AVAudioFormat, onInput: @escaping @Sendable (AnalyzerInput) -> Void) {
        self.processes = processes
        self.targetFormat = targetFormat
        self.onInput = onInput
    }

    func start() throws {
        let description = processes.isEmpty
            ? CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            : CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the audio tap")

        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &streamDescription), "read the audio format")
        guard let sourceFormat = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CaptureError.failed("read the audio format")
        }
        self.sourceFormat = sourceFormat
        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wordbridge Meeting Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create the audio device")

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.handle(input)
        }, "start listening")
        try check(AudioDeviceStart(aggregateID, procID), "start listening")
    }

    private func handle(_ input: UnsafePointer<AudioBufferList>) {
        guard let sourceFormat, let converter,
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: input, deallocator: nil),
              let output = AudioConversion.convert(source, with: converter, to: targetFormat)
        else { return }
        onInput(AnalyzerInput(buffer: output))
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            if let procID { AudioDeviceDestroyIOProcID(aggregateID, procID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
    }

    deinit { stop() }

    private func check(_ status: OSStatus, _ action: String) throws {
        guard status == noErr else { throw CaptureError.failed(action, status) }
    }

    enum CaptureError: LocalizedError {
        case failed(String, OSStatus = 0)
        var errorDescription: String? {
            switch self {
            case .failed(let action, let status):
                "Couldn't \(action) (\(status)). Allow Wordbridge in System Settings › Privacy & Security › "
                    + "Screen & System Audio Recording, under System Audio Recording Only."
            }
        }
    }
}
