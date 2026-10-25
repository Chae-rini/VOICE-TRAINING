import Accelerate
import AVFoundation
import Observation

/// 마이크 권한 상태.
enum MicrophonePermission {
    case undetermined
    case granted
    case denied
}

/// 마이크 입력과 녹음·재생을 맡는다.
/// 연습을 시작하면 정지할 때까지 녹음을 이어 가되, 최근 N초(연습 시간)만 남긴다.
/// "지금 들어보기"를 누르면 그 N초를 들려주고, 끝나면 숨을 고른 뒤 자동으로 다시 녹음한다 (PracticeLoop 순서).
/// 녹음은 메모리에만 두고, 사용자가 공유를 고르면 임시 파일로, ‘기록에 남기기’를 누르면 기기 안 기록으로 만든다.
/// 정지하면 연습 한 번의 요약(숫자만)을 기록에 남긴다.
@MainActor
@Observable
final class AudioInputManager {
    /// 연습 기록을 저장하는 곳 (기기 안)
    let archive: PracticeArchive
    private(set) var loop = PracticeLoop()
    private(set) var permission: MicrophonePermission
    /// 지금(또는 마지막) 녹음 한 번의 피치 기록. 다시 들을 때 처음부터 그릴 수 있게 녹음 길이만큼 보관한다.
    private(set) var history = PitchHistory(retention: PracticeDuration.range.upperBound + 2)
    /// 녹음 중 화면 위에 크게 보여줄 현재 피치 [Hz]. 무음이면 nil.
    private(set) var currentFrequency: Double?
    /// 그래프의 "지금"을 어느 시각으로 볼지 (실시간 / 멈춤 / 녹음 다시 듣기)
    private(set) var graphClock = GraphClock.frozen(nil)
    private(set) var errorMessage: String?
    /// 오래 연습했을 때 목을 쉬어 가라는 안내. 다음 연습이나 파일 불러오기 전까지 남겨 둔다.
    private(set) var restMessage: String?
    /// 듣기·숨 고르기의 시작~끝 시각. 남은 시간 표시에 쓴다.
    private(set) var phaseInterval: ClosedRange<Date>?
    /// 지금 녹음을 시작한 시각. 녹음한 시간 표시에 쓴다.
    private(set) var recordingStart: Date?
    /// 녹음 한 번이 끝날 때마다 1씩 늘어난다. 화면이 이 값을 보고 가벼운 진동을 울린다.
    private(set) var finishedTakeCount = 0
    /// 쉬어 가기 안내를 할 때마다 1씩 늘어난다. 화면이 이 값을 보고 진동을 울린다.
    private(set) var restReminderCount = 0
    /// 다시 들을 수 있는 마지막 녹음이 있는지.
    private(set) var hasLastTake = false
    /// 마지막 녹음의 이름("방금 녹음" 또는 불러온 파일 이름)
    private(set) var lastTakeTitle: String?
    /// [s] 마지막 녹음의 길이
    private(set) var lastTakeDuration: TimeInterval?
    /// 마지막 녹음을 이미 기록에 남겼는지
    private(set) var lastTakeIsSaved = false
    /// 마지막 녹음을 기록에 남기는 중인지
    private(set) var isSavingTake = false
    /// 녹음 파일을 분석하는 중인지
    private(set) var isAnalyzingFile = false
    /// 잠깐 보여줄 안내 (예: 긴 파일은 앞부분만 불러왔다는 안내)
    private(set) var infoMessage: String?
    /// 내 목소리 재기의 결과. 재는 화면이 보여 주고 저장하거나 닫으면 지운다.
    private(set) var measurement: VoiceBaseline.Measurement?
    /// 모음 하나를 잰 결과. [모음] 탭이 저장한 뒤 지운다.
    private(set) var vowelResult: VowelResult?
    /// 지금 재고 있는 모음 (상태 표시용)
    private(set) var measuringVowel: KoreanVowel?

    struct VowelResult: Equatable {
        let vowel: KoreanVowel
        /// nil이면 목소리가 너무 짧게 잡혀 저장하지 않음
        let entry: VowelMap.Entry?
    }

    var isRunning: Bool { loop.isActive }

    // 녹음과 재생은 오디오 설정이 달라서 엔진을 따로 쓰고, 단계마다 새로 만든다.
    // 설정을 바꾼 뒤에 만든 엔진은 바뀐 장치 상태를 처음부터 그대로 받아들인다.
    @ObservationIgnored private var recordingEngine: AVAudioEngine?
    @ObservationIgnored private var playbackEngine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var recorder: TakeRecorder?
    @ObservationIgnored private var lastTake: RecordedTake? {
        didSet { lastTakeIsSaved = false }
    }
    /// 지금 하고 있는 연습 한 번의 기록. 연습 중에만 있다.
    @ObservationIgnored private var sessionLog: PracticeSessionLog?
    /// [s] "지금 들어보기"를 누르면 들려줄 최근 길이
    @ObservationIgnored private var keepDuration: TimeInterval = PracticeDuration.defaultSeconds
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    @ObservationIgnored private var restReminderTask: Task<Void, Never>?
    /// 지금 재는 것: 내 기준 목소리, 또는 모음 하나
    @ObservationIgnored private var measuringTarget = MeasuringTarget.baseline

    private enum MeasuringTarget {
        case baseline
        case vowel(KoreanVowel)
    }
    @ObservationIgnored private var isTapInstalled = false
    @ObservationIgnored private var lastVoicedTime: TimeInterval = 0
    @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var engineObservers: [any NSObjectProtocol] = []

    /// 소리가 잠깐 끊겨도 이 시간 [s] 동안은 마지막 피치를 계속 보여준다.
    private let displayHoldTime: TimeInterval = 0.25
    private let tapBufferSize: AVAudioFrameCount = 2048
    /// [s] 재생이 스피커에서 실제로 끝날 때까지의 여유
    private let playbackTailMargin: TimeInterval = 0.2

    private struct RecordedTake {
        let id = UUID()
        /// 들려줄 수 있게 키운 소리
        let buffer: AVAudioPCMBuffer
        /// [s] 첫 샘플의 시각. 피치 기록과 같은 시계를 쓴다 (불러온 파일은 0)
        let startTime: TimeInterval
        /// 재생용으로 곱한 배율. 원래 소리 = buffer ÷ playbackGain
        let playbackGain: Float
        /// 녹음을 마친(또는 파일을 불러온) 때
        let recordedAt = Date.now
        /// 기록에 남길 때의 제목. 불러온 파일은 파일 이름, 방금 녹음한 것은 빈 글자
        let archiveTitle: String
        /// 연습 중에 녹음했으면 그 연습의 언어. 불러온 파일은 nil (남길 때 고른 언어를 쓴다)
        let language: PracticeLanguage?
    }

    /// 예약해 둔 다음 단계. 녹음은 사용자가 멈출 때까지 이어지므로 예약하지 않는다.
    private enum Step {
        case finishListening
        case finishCountdown
        case finishMeasuring
    }

    /// `archive`를 주지 않으면 앱 전체가 함께 쓰는 저장소를 쓴다.
    init(archive: PracticeArchive? = nil) {
        self.archive = archive ?? .shared
        permission = Self.readPermission()
        observeInterruptions()
    }

    /// 설정 앱에서 권한을 바꾸고 돌아왔을 때 다시 읽는다.
    func refreshPermission() {
        permission = Self.readPermission()
    }

    /// 마이크 권한을 처음이면 묻고, 쓸 수 있으면 true.
    private func ensurePermission() async -> Bool {
        if permission == .undetermined {
            let granted = await AVAudioApplication.requestRecordPermission()
            permission = granted ? .granted : .denied
        }
        return permission == .granted
    }

    /// 연습을 시작한다. 정지할 때까지 녹음 → (들어보기를 누르면) 듣기 → 다시 녹음을 이어 간다.
    /// `duration` [s]: 들어보기를 누르면 들려줄 최근 길이. `language`: 기록에 함께 남길 연습 언어.
    func start(duration: TimeInterval, language: PracticeLanguage) async {
        guard !isRunning, !isAnalyzingFile else { return }
        errorMessage = nil
        infoMessage = nil
        restMessage = nil
        guard await ensurePermission(), !isRunning else { return }

        keepDuration = duration
        loop = PracticeLoop()
        loop.start()
        sessionLog = PracticeSessionLog(language: language)
        startRestReminders()
        beginRecording()
    }

    /// 녹음 중에 누르면, 남겨 둔 최근 녹음(최대 N초)을 바로 들려준다. 다 들으면 자동으로 다시 녹음한다.
    func listenNow() {
        guard case .recording = loop.phase else { return }
        finishRecording()
    }

    /// 듣는 중에 바로 다음 단계로 넘어간다.
    func skipListening() {
        guard case .listening = loop.phase else { return }
        finishListening()
    }

    /// 연습이 끝난 뒤 마지막 녹음을 다시 듣는다.
    func replayLastTake() {
        guard !isRunning, let lastTake else { return }
        errorMessage = nil
        loop.startReplay()
        play(lastTake)
    }

    /// 녹음 파일(음성 메모 등)을 불러와 피치를 미리 계산한 뒤, 곧바로 재생하며 곡선을 보여준다.
    /// 파일은 기기 안에서 읽기만 한다. `title`을 주지 않으면 파일 이름을 쓴다. 불러왔으면 true.
    @discardableResult
    func importRecording(from url: URL, title: String? = nil) async -> Bool {
        guard !isRunning, !isAnalyzingFile else { return false }
        errorMessage = nil
        infoMessage = nil
        restMessage = nil
        isAnalyzingFile = true
        defer { isAnalyzingFile = false }

        let analysis: AudioFileAnalyzer.Analysis
        do {
            analysis = try await analyzeFile(at: url)
        } catch {
            errorMessage = "이 파일을 읽지 못했어요. 음성 메모에서 ‘파일에 저장’한 녹음 파일인지 확인해 주세요."
            return false
        }
        guard !isRunning,
              let playback = TakeRecorder.makePlaybackBuffer(samples: analysis.samples, sampleRate: analysis.sampleRate) else {
            return false
        }

        history = PitchHistory(retention: analysis.duration + 2)
        history.append(contentsOf: analysis.readings)
        let title = title ?? url.deletingPathExtension().lastPathComponent
        lastTake = RecordedTake(buffer: playback.buffer, startTime: 0, playbackGain: playback.gain,
                                archiveTitle: title, language: nil)
        hasLastTake = true
        lastTakeTitle = title
        lastTakeDuration = analysis.duration
        if analysis.wasTruncated {
            infoMessage = "5분이 넘는 녹음이라 앞 5분만 불러왔어요."
        }
        replayLastTake()
        return true
    }

    /// [기록] 탭에서 남긴 녹음을 다시 열어 재생하며 곡선을 보여 준다. 이미 기록에 있으므로 ‘기록에 남겼어요’로 표시한다.
    func openSavedRecording(_ recording: SavedRecording) async {
        if await importRecording(from: archive.fileURL(for: recording), title: recording.displayTitle) {
            lastTakeIsSaved = true
        }
    }

    /// 녹음 파일을 읽어 피치를 미리 계산한다. 시간이 걸리므로 화면이 멈추지 않게 백그라운드에서 한다.
    private func analyzeFile(at url: URL) async throws -> AudioFileAnalyzer.Analysis {
        try await Task.detached(priority: .userInitiated) {
            // 파일 앱에서 고른 파일은 읽는 동안만 접근 허락을 받는다.
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing { url.stopAccessingSecurityScopedResource() }
            }
            return try AudioFileAnalyzer.analyze(url: url)
        }.value
    }

    // MARK: - 내 목소리 재기

    /// 내 목소리 재기: 마이크로 10초 녹음해 기준 목소리를 잰다 (연습과 같은 YIN 분석). 결과는 `measurement`.
    func measureBaseline() async {
        guard !isRunning, !isAnalyzingFile else { return }
        errorMessage = nil
        measurement = nil
        guard await ensurePermission(), !isRunning else { return }
        measuringTarget = .baseline
        startMeasuring(seconds: VoiceBaseline.recordingSeconds)
    }

    /// 내 모음 지도: 모음 하나를 3초 동안 길게 낸 소리로 F1·F2를 잰다. 결과는 `vowelResult`.
    func measureVowel(_ vowel: KoreanVowel) async {
        guard !isRunning, !isAnalyzingFile else { return }
        errorMessage = nil
        vowelResult = nil
        guard await ensurePermission(), !isRunning else { return }
        measuringTarget = .vowel(vowel)
        measuringVowel = vowel
        startMeasuring(seconds: VowelMap.recordingSeconds)
    }

    /// 녹음 파일(음성 메모 등)에 담긴 모음 하나로 F1·F2를 잰다. 파일 전체를 그 모음으로 본다.
    func measureVowel(_ vowel: KoreanVowel, fromFile url: URL) async {
        guard !isRunning, !isAnalyzingFile else { return }
        errorMessage = nil
        vowelResult = nil
        isAnalyzingFile = true
        defer { isAnalyzingFile = false }
        do {
            let readings = try await analyzeFile(at: url).readings
            vowelResult = VowelResult(vowel: vowel, entry: VowelMap.measure(readings))
        } catch {
            errorMessage = "이 파일을 읽지 못했어요. 녹음(오디오) 파일인지 확인해 주세요."
        }
    }

    /// 모음을 잰 결과를 지운다 (화면이 저장한 뒤).
    func clearVowelResult() {
        vowelResult = nil
    }

    private func startMeasuring(seconds: TimeInterval) {
        keepDuration = seconds
        loop.startMeasuring()
        beginRecording()
        guard case .measuring = loop.phase else { return }  // 마이크를 못 켰으면 이미 정지됨
        recordingStart = nil  // 재는 동안에는 남은 시간을 보여 준다
        schedule(.finishMeasuring, after: seconds)
    }

    /// 녹음 파일(음성 메모 등)로 기준 목소리를 잰다. 파일은 기기 안에서 읽기만 한다.
    func measureBaseline(fromFile url: URL) async {
        guard !isRunning, !isAnalyzingFile else { return }
        errorMessage = nil
        measurement = nil
        isAnalyzingFile = true
        defer { isAnalyzingFile = false }
        do {
            measurement = VoiceBaseline.measure(try await analyzeFile(at: url).readings)
        } catch {
            errorMessage = "이 파일을 읽지 못했어요. 녹음(오디오) 파일인지 확인해 주세요."
        }
    }

    /// 잰 결과를 지운다 (다시 재거나 화면을 닫을 때).
    func clearMeasurement() {
        measurement = nil
        errorMessage = nil
    }

    private func finishMeasuring() {
        removeTap()
        recorder = nil
        currentFrequency = nil
        graphClock = .frozen(graphClock.endTime(now: AudioClock.now))
        shutDown()
        loop.stop()
        switch measuringTarget {
        case .baseline:
            measurement = VoiceBaseline.measure(history.readings)
        case .vowel(let vowel):
            vowelResult = VowelResult(vowel: vowel, entry: VowelMap.measure(history.readings))
            measuringVowel = nil
        }
    }

    /// 다른 앱(음성 메모 등)의 공유 창에서 이 앱으로 보낸 녹음을 연다.
    /// iOS가 앱 안에 복사해 준 파일이라, 메모리로 읽은 뒤에는 지운다.
    func openSharedRecording(_ url: URL) async {
        stop()  // 사용자가 직접 보낸 파일이므로 하던 연습보다 먼저 연다
        await importRecording(from: url)
        if Self.isInboxCopy(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// iOS가 이 앱 안에 복사해 준 파일인지. 다른 곳의 원본을 지우지 않도록 이 경우에만 지운다.
    /// 복사 위치는 tmp/<번들 ID>-Inbox(iOS 27 시뮬레이터에서 확인)이고, 예전 iOS는 Documents/Inbox를 썼다.
    static func isInboxCopy(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        var inboxes = [
            fileManager.temporaryDirectory
                .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "")-Inbox", isDirectory: true),
        ]
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            inboxes.append(documents.appendingPathComponent("Inbox", isDirectory: true))
        }
        let path = url.resolvingSymlinksInPath().path
        return inboxes.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    /// 마지막 녹음을 기록에 남긴다 (사용자가 ‘기록에 남기기’를 눌렀을 때만). 소리는 m4a로 기기 안에 저장한다.
    /// `summary`: 화면에 보이는 그 녹음의 요약. `language`: 불러온 파일일 때 붙일 언어 (연습 중 녹음은 그 연습의 언어).
    func saveLastTake(summary: PitchSummary, memo: String, language: PracticeLanguage) async {
        guard let take = lastTake, !lastTakeIsSaved, !isSavingTake, let samples = originalSamples(of: take) else { return }
        isSavingTake = true
        defer { isSavingTake = false }
        do {
            try await archive.saveRecording(
                samples: samples, sampleRate: take.buffer.format.sampleRate, summary: summary,
                title: take.archiveTitle, memo: memo, language: take.language ?? language, recordedAt: take.recordedAt
            )
            // 저장하는 동안 새 녹음으로 바뀌었으면 새 녹음은 아직 남기지 않은 것이다.
            if lastTake?.id == take.id {
                lastTakeIsSaved = true
            }
        } catch {
            errorMessage = "녹음을 기록에 남기지 못했어요. 기기 저장 공간을 확인해 주세요."
        }
    }

    /// 재생용으로 키우기 전의 원래 소리
    private func originalSamples(of take: RecordedTake) -> [Float]? {
        guard let channel = take.buffer.floatChannelData?[0] else { return nil }
        let boosted = Array(UnsafeBufferPointer(start: channel, count: Int(take.buffer.frameLength)))
        return take.playbackGain == 1 ? boosted : vDSP.divide(boosted, take.playbackGain)
    }

    /// 마지막 녹음의 원래 소리를 공유용 WAV 파일로 임시 폴더에 만든다. 다 쓰면 지워도 된다.
    func exportLastTake() throws -> URL {
        guard let lastTake, let original = originalSamples(of: lastTake) else {
            throw AudioFileAnalyzer.AnalysisError.emptyFile
        }

        let directory = FileManager.default.temporaryDirectory
        // 지난번에 공유하려고 만든 파일은 지운다 (임시 폴더라 iOS도 때때로 비운다).
        if let oldFiles = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in oldFiles where file.lastPathComponent.hasPrefix("VoicePractice-") {
                try? FileManager.default.removeItem(at: file)
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]  // 예: 20261025T061230
        formatter.timeZone = .current
        let url = directory.appendingPathComponent("VoicePractice-\(formatter.string(from: .now)).wav")
        try AudioFileAnalyzer.writeWAV(samples: original, sampleRate: lastTake.buffer.format.sampleRate, to: url)
        return url
    }

    /// 연습을 멈춘다 (직접 정지, 전화·알람, 이어폰 연결 변화, 백그라운드 전환).
    /// 녹음 도중이었다면 거기까지 녹음한 소리를 남겨 다시 들을 수 있게 한다.
    func stop() {
        if case .recording = loop.phase {
            removeTap()
            keepTake()
        }
        if isRunning {
            graphClock = .frozen(graphClock.endTime(now: AudioClock.now))
        }
        restReminderTask?.cancel()
        restReminderTask = nil
        recordingStart = nil
        measuringVowel = nil
        shutDown()
        loop.stop()
        finishSession()
    }

    /// 연습 한 번을 마치며 요약(숫자만)을 기록에 남긴다. 30초 넘게 연습하고 목소리가 5초 넘게 잡혔을 때만.
    private func finishSession() {
        guard let log = sessionLog else { return }
        sessionLog = nil
        // 목표 범위는 연습 중에도 옮길 수 있으므로, 정지한 때의 값과 비교한다.
        guard let summary = log.finish(at: .now, target: TargetRangeStore.savedTarget(in: .standard)) else { return }
        archive.saveSession(summary)
        infoMessage = "연습 기록을 남겼어요 · \(PitchSummary.durationLabel(summary.pitch.duration))"
    }

    // MARK: - 단계 진행

    private func beginRecording() {
        let engine: AVAudioEngine
        let format: AVAudioFormat
        do {
            (engine, format) = try makeRecordingEngine()
        } catch {
            fail("마이크를 시작하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }

        let recorder = TakeRecorder(sampleRate: format.sampleRate, keepSeconds: keepDuration)
        self.recorder = recorder
        let processor = PitchTapProcessor(sampleRate: format.sampleRate, recorder: recorder) { [weak self] readings in
            guard let self else { return }
            // 오디오 스레드 → 메인 스레드로 넘겨서 화면에 반영한다.
            Task { @MainActor in
                self.receive(readings)
            }
        }
        processor.installTap(on: engine.inputNode, bufferSize: tapBufferSize, format: format)
        isTapInstalled = true

        // 들려줄 최근 N초 동안의 곡선을 다시 그릴 수 있게 그만큼 보관한다.
        history = PitchHistory(retention: keepDuration + 2)
        currentFrequency = nil
        lastVoicedTime = 0
        do {
            engine.prepare()
            try engine.start()
        } catch {
            fail("마이크를 시작하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }
        graphClock = .live
        phaseInterval = nil
        recordingStart = .now
        sessionLog?.beginTake()  // 연습 중일 때만 있다 (내 목소리 재기는 기록하지 않음)
    }

    private func finishRecording() {
        removeTap()
        currentFrequency = nil
        recordingStart = nil
        let take = keepTake()
        finishedTakeCount += 1
        loop.recordingFinished()
        if let take {
            play(take)
        } else {
            finishListening()  // 녹음된 소리가 없으면 듣기를 건너뛴다
        }
    }

    private func play(_ take: RecordedTake) {
        let player: AVAudioPlayerNode
        do {
            player = try startPlaybackEngine(format: take.buffer.format)
        } catch {
            fail("소리를 재생하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }
        player.scheduleBuffer(take.buffer, at: nil, options: [], completionHandler: nil)
        player.play()
        graphClock = .replay(takeStart: take.startTime, playbackStart: AudioClock.now)

        let length = Double(take.buffer.frameLength) / take.buffer.format.sampleRate  // [s]
        schedule(.finishListening, after: length + playbackTailMargin)
    }

    private func finishListening() {
        stopEngines()
        graphClock = .frozen(graphClock.endTime(now: AudioClock.now))
        loop.listeningFinished()

        if case .countdown = loop.phase {
            schedule(.finishCountdown, after: PracticeLoop.countdownSeconds)
        } else {
            shutDown()  // 마지막 녹음 다시 듣기가 끝남
        }
    }

    private func finishCountdown() {
        loop.countdownFinished()
        beginRecording()
    }

    /// 지금 단계를 `seconds`초 뒤에 끝내도록 예약한다. 남은 시간 표시도 함께 맞춘다.
    private func schedule(_ step: Step, after seconds: TimeInterval) {
        phaseTask?.cancel()
        let start = Date.now
        phaseInterval = start...start.addingTimeInterval(seconds)
        phaseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.perform(step)
        }
    }

    private func perform(_ step: Step) {
        switch step {
        case .finishListening: finishListening()
        case .finishCountdown: finishCountdown()
        case .finishMeasuring: finishMeasuring()
        }
    }

    /// 정지할 때까지 쉬지 않고 연습하면, 일정 시간마다 목을 쉬어 가라고 알린다 (성대 건강). 연습은 멈추지 않는다.
    private func startRestReminders() {
        restReminderTask?.cancel()
        restReminderTask = Task { [weak self] in
            var elapsed: TimeInterval = 0  // [s]
            while true {
                try? await Task.sleep(for: .seconds(PracticeLoop.restReminderInterval))
                guard !Task.isCancelled, let self else { return }
                elapsed += PracticeLoop.restReminderInterval
                self.restMessage = PracticeLoop.restMessage(after: elapsed)
                self.restReminderCount += 1
            }
        }
    }

    private func fail(_ message: String) {
        stop()
        errorMessage = message
    }

    // MARK: - 장치

    /// 녹음용 엔진을 새로 만든다. 탭은 이 엔진의 마이크 입력에 건다.
    private func makeRecordingEngine() throws -> (AVAudioEngine, AVAudioFormat) {
        stopEngines()
        let session = AVAudioSession.sharedInstance()
        // .measurement: iOS의 자동 음량 조절·음성 보정을 꺼서 분석값이 왜곡되지 않게 한다.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioInputError.noInputDevice
        }
        observeConfigurationChanges(of: engine)
        recordingEngine = engine
        return (engine, format)
    }

    /// 재생용 엔진을 새로 만들어 시작하고, 소리를 넣을 재생 장치를 돌려준다.
    /// .measurement 모드는 스피커 출력도 보정하지 않아 소리가 작게 들린다.
    /// 그래서 듣는 동안은 음악 앱과 같은 .playback으로 바꿔 스피커로 충분히 크게 들려준다 (기기 음량 버튼을 따른다).
    private func startPlaybackEngine(format: AVAudioFormat) throws -> AVAudioPlayerNode {
        stopEngines()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        observeConfigurationChanges(of: engine)
        playbackEngine = engine
        self.player = player
        engine.prepare()
        try engine.start()
        return player
    }

    /// 지금 쓰는 엔진을 모두 멈추고 버린다. 다음 단계는 새 엔진으로 시작한다.
    private func stopEngines() {
        removeTap()
        player?.stop()
        playbackEngine?.stop()
        recordingEngine?.stop()
        player = nil
        playbackEngine = nil
        recordingEngine = nil
        for observer in engineObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        engineObservers.removeAll()
    }

    /// 엔진·오디오 세션과 예약된 단계를 모두 끈다. 상태 표시줄의 마이크 표시도 사라진다.
    private func shutDown() {
        phaseTask?.cancel()
        phaseTask = nil
        phaseInterval = nil
        stopEngines()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        currentFrequency = nil
    }

    private func removeTap() {
        guard isTapInstalled else { return }
        recordingEngine?.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    /// 지금까지 녹음한 소리를 "마지막 녹음"으로 남긴다.
    @discardableResult
    private func keepTake() -> RecordedTake? {
        defer { recorder = nil }
        guard let recorder, let playback = recorder.makePlaybackBuffer() else { return nil }
        let take = RecordedTake(
            buffer: playback.buffer,
            startTime: recorder.startTime ?? AudioClock.now,
            playbackGain: playback.gain,
            archiveTitle: "",
            language: sessionLog?.language
        )
        lastTake = take
        hasLastTake = true
        lastTakeTitle = "방금 녹음"
        lastTakeDuration = Double(playback.buffer.frameLength) / playback.buffer.format.sampleRate
        return take
    }

    private func receive(_ readings: [PitchReading]) {
        // 녹음·재기 단계가 끝난 뒤에 늦게 도착한 결과는 버린다.
        switch loop.phase {
        case .recording:
            sessionLog?.add(readings)
        case .measuring:
            break
        default:
            return
        }
        history.append(contentsOf: readings)

        for reading in readings {
            if let frequency = reading.frequency {
                currentFrequency = frequency
                lastVoicedTime = reading.time
            } else if reading.time - lastVoicedTime > displayHoldTime {
                currentFrequency = nil
            }
        }
    }

    /// 전화·알람·다른 앱의 소리 등으로 오디오가 끊기면 안전하게 정지 상태로 바꾼다.
    private func observeInterruptions() {
        sessionObservers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            MainActor.assumeIsolated {
                self?.stop()
            }
        })
    }

    /// 이어폰을 꽂거나 빼서 입출력 장치가 바뀌면 엔진이 스스로 멈추므로, 연습도 안전하게 멈춘다.
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        engineObservers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        })
    }

    private static func readPermission() -> MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .undetermined
        }
    }
}

enum AudioInputError: Error {
    case noInputDevice
}

/// 오디오 샘플과 같은 시계. 탭 버퍼의 시각(hostTime)과 그래프의 "지금"을 같은 기준으로 맞춘다.
nonisolated enum AudioClock {
    /// [s] 기기가 켜진 뒤 흐른 시간
    static var now: TimeInterval {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }
}

/// 오디오 스레드에서만 쓰는 객체.
/// 탭 버퍼를 이어 붙여 2048샘플 창을 절반씩 겹치며 밀고, 창마다 PitchDetector를 돌린다.
/// iOS가 탭 버퍼 크기를 요청과 다르게 줄 때도 분석 간격이 일정하게 유지된다.
/// 들어온 소리는 다시 듣기용으로 TakeRecorder에도 그대로 모은다.
///
/// 탭 블록은 한 번에 하나씩 순서대로 불리므로, 내부 상태를 잠그지 않아도 겹쳐 쓰이지 않는다.
private nonisolated final class PitchTapProcessor: @unchecked Sendable {
    private let detector: PitchDetector
    private let formantAnalyzer: FormantAnalyzer
    private let recorder: TakeRecorder
    private let sampleRate: Double  // [Hz]
    private let hopLength: Int      // [샘플] 다음 창으로 미는 간격
    private let onReadings: @Sendable ([PitchReading]) -> Void

    private var pending: [Float] = []
    private var pendingStartTime: TimeInterval = 0  // [s] pending[0] 샘플의 시각

    init(sampleRate: Double, recorder: TakeRecorder, onReadings: @escaping @Sendable ([PitchReading]) -> Void) {
        let detector = PitchDetector(sampleRate: sampleRate)
        self.detector = detector
        formantAnalyzer = FormantAnalyzer(sampleRate: sampleRate)
        self.recorder = recorder
        self.sampleRate = sampleRate
        hopLength = detector.frameLength / 2  // 48kHz에서 약 21ms마다 한 점
        self.onReadings = onReadings
    }

    func installTap(on node: AVAudioNode, bufferSize: AVAudioFrameCount, format: AVAudioFormat) {
        // 탭 블록을 메인 액터 밖(이 nonisolated 메서드 안)에서 만들어야 한다.
        // 메인 액터 코드 안에서 만들면 "메인 스레드 전용"으로 추론되어, 오디오 스레드에서 불릴 때 앱이 멈춘다.
        node.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [self] buffer, time in
            process(buffer, at: time)
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let bufferStartTime = time.isHostTimeValid
            ? AVAudioTime.seconds(forHostTime: time.hostTime)
            : AudioClock.now

        recorder.append(chunk, at: bufferStartTime)

        if pending.isEmpty {
            pendingStartTime = bufferStartTime
        }
        pending.append(contentsOf: chunk)

        let frameLength = detector.frameLength
        var readings: [PitchReading] = []
        while pending.count >= frameLength {
            let frame = Array(pending[0..<frameLength])
            let estimate = detector.detect(frame)
            // 창 한가운데 시각을 그 점의 시각으로 쓴다.
            let centerTime = pendingStartTime + Double(frameLength / 2) / sampleRate
            // 목소리가 잡힌 조각에서만 포먼트를 잰다 (조각 하나에 수 µs라 오디오 스레드에서도 부담 없음).
            let formants = estimate == nil ? nil : formantAnalyzer.estimate(frame)
            readings.append(PitchReading(time: centerTime, frequency: estimate?.frequency, formants: formants))

            pending.removeFirst(hopLength)
            pendingStartTime += Double(hopLength) / sampleRate
        }

        if !readings.isEmpty {
            onReadings(readings)
        }
    }
}
