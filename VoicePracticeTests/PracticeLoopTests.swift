import AVFoundation
import Testing
@testable import VoicePractice

@MainActor
struct PracticeLoopTests {
    @Test("녹음 → 듣기 → 숨 고르기를 정한 횟수만큼 돈 뒤 끝난다")
    func fullLoop() {
        var loop = PracticeLoop(totalRounds: 2)
        loop.start()
        #expect(loop.phase == .recording(round: 1))
        loop.recordingFinished()
        #expect(loop.phase == .listening(round: 1))
        loop.listeningFinished()
        #expect(loop.phase == .countdown(nextRound: 2))
        loop.countdownFinished()
        #expect(loop.phase == .recording(round: 2))
        loop.recordingFinished()
        loop.listeningFinished()
        #expect(loop.phase == .finished)
        #expect(!loop.isActive)
    }

    @Test("한 번만 하면 녹음 → 듣기 후 바로 끝난다")
    func singleRound() {
        var loop = PracticeLoop(totalRounds: 1)
        loop.start()
        loop.recordingFinished()
        loop.listeningFinished()
        #expect(loop.phase == .finished)
    }

    @Test("늦게 도착한 신호는 무시한다 (예: 듣는 중에 '녹음 끝')")
    func ignoresOutOfOrderEvents() {
        var loop = PracticeLoop(totalRounds: 3)
        loop.start()
        loop.recordingFinished()
        loop.recordingFinished()
        loop.countdownFinished()
        #expect(loop.phase == .listening(round: 1))
    }

    @Test("어느 단계에서든 정지하면 처음 상태로 돌아간다")
    func stop() {
        var loop = PracticeLoop(totalRounds: 3)
        loop.start()
        loop.recordingFinished()
        loop.stop()
        #expect(loop.phase == .idle)
        #expect(!loop.isActive)
    }

    @Test("반복 횟수는 1~10회로 제한된다", arguments: [(0, 1), (5, 5), (99, 10)])
    func roundsAreClamped(requested: Int, expected: Int) {
        #expect(PracticeLoop(totalRounds: requested).totalRounds == expected)
    }

    @Test("마지막 녹음 다시 듣기는 연습 중이 아닐 때만 되고, 끝나면 처음 상태로 돌아간다")
    func replay() {
        var loop = PracticeLoop(totalRounds: 1)
        loop.start()
        loop.startReplay()
        #expect(loop.phase == .recording(round: 1))  // 연습 중에는 무시

        loop.recordingFinished()
        loop.listeningFinished()
        loop.startReplay()
        #expect(loop.phase == .replaying)
        #expect(loop.isActive)
        loop.listeningFinished()
        #expect(loop.phase == .idle)
    }
}

struct TakeRecorderTests {
    @Test("모은 소리를 같은 길이의 재생 버퍼로 만들고, 첫 조각의 시각을 기억한다")
    func makesBuffer() throws {
        let recorder = TakeRecorder(sampleRate: 48_000, maxSeconds: 1)
        recorder.append([0.1, 0.2, 0.3], at: 5.0)
        recorder.append([0.4], at: 6.0)

        #expect(recorder.startTime == 5.0)
        let playback = try #require(recorder.makePlaybackBuffer())
        let buffer = playback.buffer
        #expect(abs(playback.gain - TakeRecorder.playbackPeak / 0.4) < 1e-4)
        #expect(buffer.frameLength == 4)
        #expect(buffer.format.sampleRate == 48_000)
        #expect(buffer.format.channelCount == 1)

        // 가장 큰 순간(0.4)이 재생 기준 높이까지 커지고, 소리끼리의 비율은 그대로다 (일그러짐 없음).
        let channel = try #require(buffer.floatChannelData?[0])
        #expect(abs(channel[3] - TakeRecorder.playbackPeak) < 1e-5)
        #expect(abs(channel[0] / channel[3] - 0.25) < 1e-5)
    }

    @Test("재생 배율: 작은 녹음은 키우고, 큰 녹음은 그대로, 너무 작으면 +24 dB까지만", arguments: [
        (Float(0.089), Float(10)),   // −21 dBFS → 10배
        (Float(0.95), Float(1)),     // 이미 큼 → 줄이지 않음
        (Float(0.001), TakeRecorder.maxPlaybackGain),  // 거의 무음 → 최대 배율에서 멈춤
        (Float(0), Float(1)),        // 완전 무음 → 그대로
    ])
    func playbackGain(peak: Float, expected: Float) {
        #expect(abs(TakeRecorder.playbackGain(forPeak: peak) - expected) < 1e-3)
    }

    @Test("최대 길이를 넘는 소리는 버린다")
    func dropsBeyondCapacity() {
        let recorder = TakeRecorder(sampleRate: 10, maxSeconds: 1)  // 최대 10샘플
        recorder.append(Array(repeating: 0.5, count: 8), at: 0)
        recorder.append(Array(repeating: 0.5, count: 8), at: 0.8)
        #expect(recorder.sampleCount == 10)
    }

    @Test("아무것도 녹음하지 않았으면 재생 버퍼가 없다")
    func emptyRecorder() {
        let recorder = TakeRecorder(sampleRate: 48_000, maxSeconds: 1)
        #expect(recorder.makePlaybackBuffer() == nil)
        #expect(recorder.startTime == nil)
    }
}

@MainActor
struct ReplayGraphTests {
    @Test("다시 듣기 중 그래프의 '지금'은 녹음 시작 시각 + 재생된 시간이다")
    func replayClock() {
        let clock = GraphClock.replay(takeStart: 100, playbackStart: 500)
        #expect(clock.endTime(now: 503.5) == 103.5)
        #expect(clock.isMoving)
        #expect(GraphClock.frozen(42).endTime(now: 999) == 42)
        #expect(!GraphClock.frozen(42).isMoving)
    }

    @Test("다시 듣기 중에는 재생 위치 직전의 피치를 찾고, 아직 재생되지 않은 점은 그리지 않는다")
    func replayLookup() {
        var history = PitchHistory(retention: 200)
        history.append(contentsOf: [
            PitchReading(time: 0.00, frequency: 200),
            PitchReading(time: 0.02, frequency: 210),
            PitchReading(time: 0.04, frequency: nil),
            PitchReading(time: 5.00, frequency: 180),
        ])
        #expect(history.frequency(at: 0.03) == 210)
        #expect(history.frequency(at: 1.00) == nil)  // 0.3초보다 오래된 값은 쓰지 않는다
        #expect(history.voicedSegments(within: 0...1).map(\.count) == [2])
    }

    @Test("녹음 한 번 길이만큼 기록을 보관한다")
    func retention() {
        var history = PitchHistory(retention: 182)
        history.append(contentsOf: (0...180).map { PitchReading(time: Double($0), frequency: 200) })
        #expect(history.readings.count == 181)
    }
}
