import Foundation
import Testing
@testable import VoicePractice

/// 피치 그래프 가로축 (들려줄 길이만큼, 오른쪽 끝이 지금, 시간 눈금, 긴 가로축의 점 묶기)
@MainActor
struct GraphWindowTests {
    @Test("녹음 중: 오른쪽 끝이 늘 지금이고, 녹음을 시작한 때(시작선)는 왼쪽으로 흘러간다")
    func liveKeepsNowAtRight() {
        let clock = GraphClock.live(start: 100, duration: 60, round: 1)
        for now in [100.0, 130, 160] {
            let window = clock.window(now: now)
            #expect(window?.end == now)
            #expect(window?.duration == 60)
            #expect(window?.recordingStart == 100)
            #expect(window.map { $0.position(of: now) } == 1)
        }
        // 30초 녹음했으면 시작선은 가운데, 시작선 왼쪽은 비어 있다
        #expect(abs((clock.window(now: 130)?.position(of: 100) ?? 0) - 0.5) < 1e-12)
        #expect(clock.endTime(now: 130) == 130)
    }

    @Test("흐르는 중에 그래프에 보이는 구간 = 다시 들을 수 있는 소리 = 요약 수치 구간")
    func windowMatchesKeptSound() throws {
        // 100초에 녹음 시작, 25초 녹음, 들려줄 길이 10초 → 녹음 통에는 115~125초만 남는다
        let recorder = TakeRecorder(sampleRate: 48_000, keepSeconds: 10)
        recorder.append(Signal.sine(200, sampleRate: 48_000, count: 48_000 * 25), at: 100)
        let live = try #require(GraphClock.live(start: 100, duration: 10, round: 1).window(now: 125))
        let kept = try #require(recorder.startTime)
        #expect(abs(live.start - kept) < 1e-6)
        #expect(abs(live.end - 125) < 1e-9)

        var timeline = RecordingTimeline()
        timeline.beginRecording(keepSeconds: 10)
        timeline.receive((0..<1250).map { PitchReading(time: 100 + Double($0) * 0.02, frequency: 200) }, isMeasuring: false)
        let playback = try #require(recorder.makePlaybackBuffer())
        let take = timeline.keepTake(buffer: playback.buffer, startTime: kept, playbackGain: playback.gain,
                                     language: .korean, graphDuration: 10, recordingStart: 100, round: 1)
        #expect(abs(take.graphWindow.start - live.start) < 1e-6)
        #expect(abs(take.graphWindow.duration - 10) < 1e-6)
        #expect(take.readings.allSatisfy { live.position(of: $0.time) >= -1e-6 && live.position(of: $0.time) <= 1 + 1e-6 })
    }

    @Test("녹음 시작선: 첫 녹음은 ‘시작’, 다시 녹음하면 ‘2번째’ 경계선. 녹음 시작이 가로축 안일 때만 긋는다")
    func startLines() {
        let first = GraphClock.live(start: 100, duration: 60, round: 1).window(now: 120)
        #expect(first?.startLabel == "시작")
        #expect(first?.isRoundBoundary == false)
        #expect(first?.showsStartLine == true)
        #expect(abs((first.map { $0.position(of: 100) } ?? 0) - 2.0 / 3) < 1e-12)  // 20초 전 = 오른쪽에서 1/3

        let second = GraphClock.live(start: 300, duration: 60, round: 2).window(now: 330)
        #expect(second?.startLabel == "2번째")
        #expect(second?.isRoundBoundary == true)
        #expect(second?.showsStartLine == true)

        // 들려줄 길이보다 오래 녹음하면 시작선은 왼쪽 밖으로 나가 긋지 않는다
        #expect(GraphClock.live(start: 100, duration: 60, round: 1).window(now: 175)?.showsStartLine == false)
        // 녹음의 첫 소리가 녹음 시작보다 몇 ms 늦어도(녹음 통 시각) 왼쪽 끝의 시작선은 긋는다
        #expect(GraphWindow(start: 100.002, duration: 60, recordingStart: 100, round: 3).showsStartLine)
        // 불러온 파일은 시작선이 없다
        #expect(!GraphWindow(start: 0, duration: 12).showsStartLine)
    }

    @Test("녹음 중: 들려줄 길이보다 오래 녹음하면 시작선은 왼쪽 밖으로 나가고, 시간 글자는 계속 녹음 시작부터 센다")
    func liveAfterFull() {
        let window = GraphClock.live(start: 100, duration: 60, round: 1).window(now: 175)
        #expect(window?.start == 115)
        #expect(window?.end == 175)
        #expect(window?.recordingStart == 100)
        #expect(window?.showsStartLine == false)
        #expect(window?.ticks.first?.label == "0:20")
    }

    @Test("남긴 녹음의 가로축: 녹음할 때의 들려줄 길이만큼, 녹음이 더 길면 녹음 길이만큼")
    func takeWindow() throws {
        func take(seconds: Double, graphDuration: Double) throws -> RecordedTake {
            let samples = [Float](repeating: 0.1, count: Int(48_000 * seconds))
            let playback = try #require(TakeRecorder.makePlaybackBuffer(samples: samples, sampleRate: 48_000))
            return RecordedTake(buffer: playback.buffer, startTime: 50, playbackGain: playback.gain, title: "방금 녹음",
                                archiveTitle: "", language: .korean, readings: [], graphDuration: graphDuration,
                                recordingStart: 50)
        }
        // 4초 녹음(50~54초), 들려줄 길이 1분: 오른쪽 끝이 녹음 끝, 왼쪽은 비어 있다 (녹음하던 화면이 멈춘 모습 그대로)
        let short = try take(seconds: 4, graphDuration: 60).graphWindow
        #expect(short == GraphWindow(start: -6, duration: 60, recordingStart: 50, round: nil))
        #expect(short.showsStartLine)
        let long = try take(seconds: 12, graphDuration: 10).graphWindow
        #expect(abs(long.duration - 12) < 1e-9)
        // 불러온 파일은 파일 길이만큼, 시작선 없음
        let samples = [Float](repeating: 0.1, count: 48_000 * 3)
        let playback = try #require(TakeRecorder.makePlaybackBuffer(samples: samples, sampleRate: 48_000))
        let imported = RecordedTake(buffer: playback.buffer, startTime: 0, playbackGain: playback.gain, title: "파일",
                                    archiveTitle: "파일", language: nil, readings: [])
        #expect(imported.graphWindow == GraphWindow(start: 0, duration: 3, recordingStart: nil))
    }

    @Test("시간 눈금: 6개 이하가 되는 가장 촘촘한 간격", arguments: [
        (10.0, 2.0), (30.0, 5.0), (60.0, 10.0), (90.0, 15.0), (120.0, 30.0), (180.0, 30.0),
    ])
    func tickStep(duration: Double, expected: Double) {
        #expect(GraphWindow(start: 0, duration: duration).tickStep == expected)
    }

    @Test("시간 눈금 글자는 녹음을 시작한 때부터 센 분:초다 (흐른 뒤에도 이어서 센다)")
    func tickLabels() {
        let filling = GraphWindow(start: 100, duration: 60, recordingStart: 100)
        #expect(filling.ticks.map(\.label) == ["0:00", "0:10", "0:20", "0:30", "0:40", "0:50", "1:00"])
        #expect(filling.ticks.first?.time == 100)

        let sliding = GraphWindow(start: 183, duration: 60, recordingStart: 100)  // 1:23 ~ 2:23
        #expect(sliding.ticks.map(\.label) == ["1:30", "1:40", "1:50", "2:00", "2:10", "2:20"])
        #expect(sliding.ticks.first?.time == 190)

        // 녹음을 시작하기 전(시작선 왼쪽의 빈 곳)에는 눈금이 없다
        #expect(GraphWindow(start: 40, duration: 60, recordingStart: 70).ticks.map(\.label) == ["0:00", "0:10", "0:20", "0:30"])

        #expect(GraphWindow.timeLabel(0) == "0:00")
        #expect(GraphWindow.timeLabel(75) == "1:15")
        #expect(GraphWindow.timeLabel(180) == "3:00")
    }

    @Test("짧은 가로축은 점을 그대로 쓰고, 긴 가로축은 픽셀 열마다 한 점으로 묶되 무음 구간은 끊는다")
    func displaySegments() {
        // 3분 동안 0.02초마다: 처음 60초 목소리(150 Hz), 60~62초 무음, 그 뒤 다시 목소리(250 Hz)
        var history = PitchHistory(retention: 200)
        history.append(contentsOf: (0..<9000).map { index in
            let time = Double(index) * 0.02
            return PitchReading(time: time, frequency: (60..<62).contains(time) ? nil : (time < 60 ? 150 : 250))
        })
        let long = GraphWindow(start: 0, duration: 180)
        let segments = history.displaySegments(in: long, until: 180, width: 300)
        #expect(segments.count == 2)
        #expect(segments.flatMap { $0 }.count <= 300)
        #expect(segments[0].allSatisfy { $0.frequency == 150 })
        #expect(segments[1].allSatisfy { $0.frequency == 250 })

        // ‘지금’까지만 그린다
        let untilNow = history.displaySegments(in: long, until: 30, width: 300)
        #expect(untilNow.flatMap { $0 }.allSatisfy { $0.time <= 30 + 180.0 / 300 })

        // 10초 가로축(300pt면 1pt에 점 1~2개)은 묶지 않는다
        let short = history.displaySegments(in: GraphWindow(start: 0, duration: 10), until: 10, width: 300)
        #expect(short.flatMap { $0 }.count == history.readings(in: -0.5...10).filter { $0.frequency != nil }.count)
    }
}
