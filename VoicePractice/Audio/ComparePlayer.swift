import AVFoundation
import Observation

/// 두 녹음 비교 화면 전용 재생기. 남긴 녹음 두 개(A·B)를 읽어 높이 분포용 점을 내고, 하나씩 또는 A → B로 이어 들려준다.
/// 연습용 AudioInputManager와 따로 재생 엔진을 쓰므로, 연습 중에는 화면이 재생을 막는다. 화면이 닫히면 멈춘다.
/// 두 녹음 모두 가장 큰 순간을 같은 크기로 맞춰 들려준다 (연습 다시 듣기와 같은 배율 규칙). 그래서 음량 차이는 비교되지 않는다.
@MainActor
@Observable
final class ComparePlayer {
    enum Side: String {
        case a = "A"
        case b = "B"
    }

    /// 읽어 둔 녹음 하나
    struct Loaded {
        /// 들려줄 수 있게 키운 소리
        let buffer: AVAudioPCMBuffer
        /// [Hz] 목소리가 잡힌 높이들 (연습과 같은 YIN 분석)
        let voiced: [Double]

        /// [s]
        var duration: TimeInterval {
            Double(buffer.frameLength) / buffer.format.sampleRate
        }
    }

    /// [s] A → B 이어 듣기에서 두 녹음 사이에 쉬는 시간
    static let gap: TimeInterval = 0.7

    private(set) var a: Loaded?
    private(set) var b: Loaded?
    private(set) var loadingSides: Set<Side> = []
    /// 소리 파일을 읽지 못한 쪽 (숫자 기록만 비교한다)
    private(set) var failedSides: Set<Side> = []
    /// 지금 들리는 쪽
    private(set) var playing: Side?
    /// 지금 들리는 쪽의 시작~끝 (남은 시간 표시)
    private(set) var playInterval: ClosedRange<Date>?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var stepTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionObserver: (any NSObjectProtocol)?
    /// 쪽마다 마지막으로 시작한 읽기. 고르는 녹음을 빨리 바꾸면 늦게 끝난 예전 읽기는 버린다.
    @ObservationIgnored private var loadTokens: [Side: UUID] = [:]

    subscript(side: Side) -> Loaded? {
        side == .a ? a : b
    }

    /// 녹음 파일을 읽는다. 시간이 걸리므로 화면이 멈추지 않게 백그라운드에서 한다. 고르는 녹음이 바뀔 때마다 부른다.
    func load(_ side: Side, from url: URL) async {
        stop()
        let token = UUID()
        loadTokens[side] = token
        set(nil, for: side)
        failedSides.remove(side)
        loadingSides.insert(side)

        let analysis = try? await Task.detached(priority: .userInitiated) {
            try AudioFileAnalyzer.analyze(url: url)
        }.value
        guard loadTokens[side] == token else { return }
        loadingSides.remove(side)
        guard let analysis,
              let playback = TakeRecorder.makePlaybackBuffer(samples: analysis.samples, sampleRate: analysis.sampleRate) else {
            failedSides.insert(side)
            return
        }
        set(Loaded(buffer: playback.buffer, voiced: analysis.readings.compactMap(\.frequency)), for: side)
    }

    /// 한쪽을 처음부터 들려준다.
    func play(_ side: Side) {
        stop()
        playNext([side])
    }

    /// A를 다 듣고 잠깐 쉰 뒤 B를 들려준다.
    func playBoth() {
        stop()
        playNext([.a, .b])
    }

    /// 재생을 멈추고 엔진과 오디오 세션을 끈다.
    func stop() {
        stepTask?.cancel()
        stepTask = nil
        let wasPlaying = engine != nil
        stopEngine()
        playing = nil
        playInterval = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if wasPlaying {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - 내부

    private func set(_ loaded: Loaded?, for side: Side) {
        switch side {
        case .a: a = loaded
        case .b: b = loaded
        }
    }

    /// `queue`의 첫 쪽을 들려주고, 끝나면 다음 쪽으로 넘어간다. 끝 감지는 취소할 수 있는 타이머로 한다.
    private func playNext(_ queue: [Side]) {
        guard let side = queue.first, let loaded = self[side] else {
            stop()
            return
        }
        let player: AVAudioPlayerNode
        do {
            player = try startEngine(format: loaded.buffer.format)
        } catch {
            stop()
            return
        }
        player.scheduleBuffer(loaded.buffer, at: nil, options: [], completionHandler: nil)
        player.play()
        playing = side
        let start = Date.now
        playInterval = start...start.addingTimeInterval(loaded.duration)

        let rest = Array(queue.dropFirst())
        stepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(loaded.duration + Self.gap))
            guard !Task.isCancelled, let self else { return }
            if rest.isEmpty {
                self.stop()
            } else {
                self.playNext(rest)
            }
        }
    }

    /// 듣기용(.playback) 엔진을 새로 만들어 시작한다. 연습 다시 듣기와 같은 설정이라 아이폰 스피커로 충분히 크게 들린다.
    private func startEngine(format: AVAudioFormat) throws -> AVAudioPlayerNode {
        stopEngine()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.player = player
        observeInterruptions()
        return player
    }

    private func stopEngine() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    /// 전화·알람 등으로 오디오가 끊기면 멈춘다.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawType) == .began else { return }
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }
}
