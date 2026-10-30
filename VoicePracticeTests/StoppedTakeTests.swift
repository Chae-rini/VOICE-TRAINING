import AVFoundation
import Testing
@testable import VoicePractice

/// 정지로 끊은 빈 녹음이 마지막 녹음을 덮어쓰던 버그 (2026-10-26 에뮬레이터에서 실제로 녹음을 잃음, 2026-10-30 고침).
/// 반복 루프는 다 들은 뒤 다음 녹음을 스스로 시작한다. 그 새 녹음에 목소리가 거의 없을 때 정지하면 그 전 녹음을 그대로 둔다.
@MainActor
struct StoppedTakeTests {
    private let sampleRate = 48_000.0

    private func voice(_ seconds: Double) -> [Float] {
        Signal.sine(180, sampleRate: sampleRate, count: Int(sampleRate * seconds))
    }

    /// 방의 작은 잡음 (−54 dBFS 근처, 목소리로 잡히지 않는 크기)
    private func roomNoise(_ seconds: Double, seed: UInt64 = 7) -> [Float] {
        Signal.noise(count: Int(sampleRate * seconds), amplitude: 0.002, seed: seed)
    }

    /// 녹음 한 번을 흉내 내어 묶음을 만든다 (아직 마지막 녹음으로 두지는 않음). `startTime` [s]: 소리가 들어오기 시작한 시각
    private func record(_ samples: [Float], startTime: TimeInterval, into timeline: inout RecordingTimeline) throws -> RecordedTake {
        timeline.beginRecording(keepSeconds: 30)
        let readings = AudioFileAnalyzer.pitchReadings(samples, sampleRate: sampleRate).map {
            PitchReading(time: $0.time + startTime, frequency: $0.frequency, formants: $0.formants)
        }
        timeline.receive(readings, isMeasuring: false)
        let recorder = TakeRecorder(sampleRate: sampleRate, keepSeconds: 30)
        recorder.append(samples, at: startTime)
        let playback = try #require(recorder.makePlaybackBuffer())
        return timeline.makeTake(buffer: playback.buffer, startTime: try #require(recorder.startTime),
                                 playbackGain: playback.gain, language: .korean)
    }

    @Test("정지로 끊은 빈 녹음은 그 전 녹음(방금 들은 녹음)을 덮어쓰지 않고, 그래프도 그 녹음으로 돌아간다")
    func silentStoppedTakeKeepsEarlier() throws {
        var timeline = RecordingTimeline()
        let earlier = try record(voice(5), startTime: 0, into: &timeline)
        let keptEarlier = timeline.keep(earlier)
        #expect(keptEarlier)

        let silent = try record(roomNoise(4), startTime: 20, into: &timeline)
        #expect(silent.voicedSeconds == 0)
        let keptSilent = timeline.keep(silent, stopped: true)
        #expect(!keptSilent)
        #expect(timeline.lastTake?.id == earlier.id)
        let shown = timeline.display.readings.compactMap(\.frequency)
        #expect(!shown.isEmpty)
        #expect(shown.allSatisfy { abs($0 - 180) < 5 }, "그래프가 그 전 녹음으로 돌아오지 않았다")
    }

    @Test("목소리가 0.5초보다 짧으면 버리고, 넘으면 새 녹음으로 남긴다")
    func voicedThreshold() throws {
        var timeline = RecordingTimeline()
        let earlier = try record(voice(5), startTime: 0, into: &timeline)
        timeline.keep(earlier)

        let short = try record(voice(0.3) + roomNoise(3), startTime: 20, into: &timeline)
        #expect(short.voicedSeconds > 0)
        #expect(short.voicedSeconds < RecordingTimeline.minimumStoppedTakeVoicedSeconds)
        let keptShort = timeline.keep(short, stopped: true)
        #expect(!keptShort)
        #expect(timeline.lastTake?.id == earlier.id)

        let spoken = try record(voice(1) + roomNoise(3), startTime: 40, into: &timeline)
        #expect(spoken.voicedSeconds >= RecordingTimeline.minimumStoppedTakeVoicedSeconds)
        let keptSpoken = timeline.keep(spoken, stopped: true)
        #expect(keptSpoken)
        #expect(timeline.lastTake?.id == spoken.id)
    }

    @Test("그 전 녹음이 없으면 빈 녹음도 마지막 녹음으로 남긴다 (지금과 같게)")
    func silentTakeWithoutEarlier() throws {
        var timeline = RecordingTimeline()
        let silent = try record(roomNoise(4), startTime: 0, into: &timeline)
        let kept = timeline.keep(silent, stopped: true)
        #expect(kept)
        #expect(timeline.lastTake?.id == silent.id)
    }

    @Test("‘지금 들어보기’로 끝낸 녹음은 목소리가 없어도 그대로 남긴다 (정지가 아닐 때)")
    func listenNowKeepsSilentTake() throws {
        var timeline = RecordingTimeline()
        let earlier = try record(voice(5), startTime: 0, into: &timeline)
        timeline.keep(earlier)
        let silent = try record(roomNoise(4), startTime: 20, into: &timeline)
        let kept = timeline.keep(silent)
        #expect(kept)
        #expect(timeline.lastTake?.id == silent.id)
    }
}
