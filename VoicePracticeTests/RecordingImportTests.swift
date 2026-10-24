import AVFoundation
import Foundation
import Testing
@testable import VoicePractice

struct AudioFileAnalyzerTests {
    let sampleRate = 48_000.0  // [Hz]

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).wav")
    }

    @Test("녹음 파일을 읽어 피치를 계산하면 원래 높이가 나온다")
    func analyzesFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let tone = Signal.sine(220, sampleRate: sampleRate, count: Int(sampleRate * 2))  // 2초
        try AudioFileAnalyzer.writeWAV(samples: tone, sampleRate: sampleRate, to: url)

        let analysis = try AudioFileAnalyzer.analyze(url: url)
        #expect(abs(analysis.duration - 2) < 0.01)
        #expect(!analysis.wasTruncated)
        let voiced = analysis.readings.compactMap(\.frequency).sorted()
        #expect(voiced.count > analysis.readings.count * 9 / 10)
        #expect(abs(PitchSummary.percentile(voiced, 0.5) - 220) < 1)
    }

    @Test("최대 길이보다 긴 파일은 앞부분만 불러온다")
    func truncatesLongFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioFileAnalyzer.writeWAV(samples: Signal.sine(200, sampleRate: sampleRate, count: Int(sampleRate * 2)),
                                       sampleRate: sampleRate, to: url)

        let analysis = try AudioFileAnalyzer.analyze(url: url, maxSeconds: 1)
        #expect(abs(analysis.duration - 1) < 0.01)
        #expect(analysis.wasTruncated)
    }

    @Test("스테레오는 두 채널을 평균해 하나로 합친다")
    func mixesStereoToMono() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channels = try #require(buffer.floatChannelData)
        for i in 0..<4 {
            channels[0][i] = 0.5
            channels[1][i] = 0.1
        }
        let mono = AudioFileAnalyzer.mono(buffer)
        #expect(mono.count == 4)
        #expect(mono.allSatisfy { abs($0 - 0.3) < 1e-6 })
    }

    @Test("공유용 WAV를 다시 읽으면 같은 소리다 (16비트 반올림 오차 이내)")
    func wavRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let samples: [Float] = [0.5, -0.25, 0, 0.125, -0.5]
        try AudioFileAnalyzer.writeWAV(samples: samples, sampleRate: sampleRate, to: url)

        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 5))
        try file.read(into: buffer)
        let readBack = AudioFileAnalyzer.mono(buffer)
        #expect(readBack.count == samples.count)
        for (a, b) in zip(samples, readBack) {
            #expect(abs(a - b) < 1.0 / 16_000)
        }
    }
}

@MainActor
struct SharedRecordingTests {
    @Test("공유로 받은 복사본(tmp/<번들 ID>-Inbox, Documents/Inbox 안)만 지울 대상이고, 다른 위치의 파일은 아니다")
    func onlyInboxCopiesAreRemovable() throws {
        let documents = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let bundleID = try #require(Bundle.main.bundleIdentifier)
        let temporary = FileManager.default.temporaryDirectory
        #expect(AudioInputManager.isInboxCopy(temporary.appendingPathComponent("\(bundleID)-Inbox/새로운 녹음.m4a")))
        #expect(AudioInputManager.isInboxCopy(documents.appendingPathComponent("Inbox/새로운 녹음.m4a")))
        #expect(!AudioInputManager.isInboxCopy(documents.appendingPathComponent("새로운 녹음.m4a")))
        #expect(!AudioInputManager.isInboxCopy(documents.appendingPathComponent("Inbox")))
        #expect(!AudioInputManager.isInboxCopy(documents.appendingPathComponent("Inbox2/a.m4a")))
        #expect(!AudioInputManager.isInboxCopy(FileManager.default.temporaryDirectory.appendingPathComponent("a.m4a")))
    }
}

@MainActor
struct PitchSummaryTests {
    /// 0.02초 간격, 가운데 무음 2개를 낀 다섯 점: 100, 150, 200, 250, 300 Hz
    let readings: [PitchReading] = [
        PitchReading(time: 0.00, frequency: 100),
        PitchReading(time: 0.02, frequency: 150),
        PitchReading(time: 0.04, frequency: nil),
        PitchReading(time: 0.06, frequency: 200),
        PitchReading(time: 0.08, frequency: nil),
        PitchReading(time: 0.10, frequency: 250),
        PitchReading(time: 0.12, frequency: 300),
    ]

    @Test("중앙값·아래 10%·위 10%·목표 범위 안 비율·목소리 시간")
    func summarizes() throws {
        let summary = try #require(PitchSummary(readings: readings, duration: 3, target: 180...220))
        #expect(summary.median == 200)
        #expect(abs(summary.p10 - 120) < 1e-9)  // 100과 150 사이 40% 지점
        #expect(abs(summary.p90 - 280) < 1e-9)  // 250과 300 사이 60% 지점
        #expect(abs(try #require(summary.inTargetFraction) - 0.2) < 1e-9)
        #expect(abs(summary.voicedSeconds - 0.1) < 1e-9)
    }

    @Test("목소리가 한 번도 안 잡혔으면 요약이 없다")
    func noVoice() {
        let silent = [PitchReading(time: 0, frequency: nil), PitchReading(time: 0.02, frequency: nil)]
        #expect(PitchSummary(readings: silent, duration: 1, target: 180...220) == nil)
    }

    @Test("목표 범위가 아직 없으면 비율을 비워 두고, 요청문에도 정하지 않았다고 쓴다")
    func noTarget() throws {
        let summary = try #require(PitchSummary(readings: readings, duration: 3, target: nil))
        #expect(summary.inTargetFraction == nil)
        let text = summary.feedbackRequest(title: "방금 녹음", includesAudio: true)
        #expect(text.contains("내 목표 범위: 아직 정하지 않음"))
        #expect(text.contains("높이거나 낮추는 방향은 가정하지 말아 주세요"))
    }

    @Test("녹음 길이 표시", arguments: [(45.0, "45초"), (60.0, "1분"), (83.4, "1분 23초")])
    func durationLabel(seconds: Double, expected: String) {
        #expect(PitchSummary.durationLabel(seconds) == expected)
    }

    @Test("피드백 요청문에 수치·목표 범위·요청 관점이 들어간다")
    func feedbackRequest() throws {
        let summary = try #require(PitchSummary(readings: readings, duration: 83, target: 180...220))
        let text = summary.feedbackRequest(title: "방금 녹음", includesAudio: true)
        for expected in ["방금 녹음 (1분 23초)", "피치 중앙값: 200 Hz", "120~280 Hz", "180~220 Hz", "20%",
                         "문장 끝 안정성", "함께 보낸 녹음 파일", "성대에 무리가 가지 않는",
                         "어둡고 무게감 있는 쪽", "높이거나 낮추는 방향은 가정하지 말고"] {
            #expect(text.contains(expected), "\(expected)")
        }
        #expect(!text.contains("밝고 가벼운 정도"))  // 한쪽 방향만 전제하던 예전 표현
    }

    @Test("글만 보낼 때는 파일이 없다고 밝히고, 음색은 짐작하지 말라고 한다")
    func textOnlyRequest() throws {
        let summary = try #require(PitchSummary(readings: readings, duration: 83, target: 180...220))
        let text = summary.feedbackRequest(title: "방금 녹음", includesAudio: false)
        #expect(text.contains("피치 중앙값: 200 Hz"))
        #expect(text.contains("녹음 파일은 보내지 않았어요"))
        #expect(text.contains("짐작하지 말아 주세요"))
        #expect(text.contains("성대에 무리가 가지 않는"))
        #expect(text.contains("높이거나 낮추는 방향은 가정하지 말고"))
        #expect(!text.contains("함께 보낸 녹음 파일"))
    }
}
