import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct RecordingComparisonTests {
    @Test("처음 짝은 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B), 두 개가 안 되면 없음")
    func defaultPair() throws {
        let dates = [Date(timeIntervalSince1970: 300), Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        let pair = try #require(RecordingComparison.defaultPair(dates, date: { $0 }))
        #expect(pair.a == dates[1])
        #expect(pair.b == dates[0])
        #expect(RecordingComparison.defaultPair([dates[0]], date: { $0 }) == nil)
    }

    @Test("높낮이 폭은 범위를 반음으로 센 값")
    func rangeSemitones() {
        #expect(abs(RecordingComparison.rangeSemitones(low: 100, high: 200) - 12) < 1e-9)
        #expect(RecordingComparison.rangeSemitones(low: 150, high: 150) == 0)
        #expect(RecordingComparison.rangeSemitones(low: 0, high: 150) == 0)
    }

    @Test("중앙값 차이는 높다·낮다는 사실과 반음 수만 말한다", arguments: [
        (150.0, 162.0, "B의 중앙값이 A보다 12 Hz 높아요 (반음 약 1.3개)."),
        (200.0, 180.0, "B의 중앙값이 A보다 20 Hz 낮아요 (반음 약 1.8개)."),
        (150.0, 150.5, "두 녹음의 중앙값이 거의 같아요 (1 Hz 미만 차이)."),
    ])
    func medianDifference(a: Double, b: Double, expected: String) {
        let text = RecordingComparison.medianDifferenceText(a: a, b: b)
        #expect(text == expected)
        for judgement in ["좋", "나빠", "개선", "남성", "여성"] {
            #expect(!text.contains(judgement))
        }
    }

    @Test("높이 분포: 5 Hz 칸마다 비율, 범위 밖 점은 칸에 넣지 않되 전체 수에는 넣는다")
    func distribution() throws {
        let bins = RecordingComparison.distribution([150, 151, 152, 157, 180], in: 150...185)
        #expect(bins.count == 7)
        #expect(bins.map(\.center) == [152.5, 157.5, 162.5, 167.5, 172.5, 177.5, 182.5])
        #expect(abs(bins[0].fraction - 0.6) < 1e-9)
        #expect(abs(bins[1].fraction - 0.2) < 1e-9)
        #expect(abs(bins[6].fraction - 0.2) < 1e-9)
        #expect(abs(bins.map(\.fraction).reduce(0, +) - 1) < 1e-9)

        let withOutlier = RecordingComparison.distribution([150, 151, 152, 157, 180, 390], in: 150...185)
        #expect(abs(withOutlier.map(\.fraction).reduce(0, +) - 5.0 / 6) < 1e-9)
        #expect(RecordingComparison.distribution([], in: 150...185).isEmpty)
    }

    @Test("분포 그래프 가로축: 두 녹음과 목표 범위가 들어가고, 드물게 튄 값은 뺀다")
    func domain() {
        let a = (0..<100).map { 140 + Double($0) * 0.2 }        // 140~160 Hz
        let b = (0..<100).map { 170 + Double($0) * 0.2 } + [395]  // 170~190 Hz, 한 번 튄 값
        let domain = RecordingComparison.domain(a, b, target: 200...220)
        #expect(domain.contains(140))
        #expect(domain.contains(190))
        #expect(domain.contains(220))
        #expect(!domain.contains(395))
        #expect(domain.upperBound - domain.lowerBound >= PracticeHistory.minimumPitchSpan)
    }

    @Test("비교 재생기: 남긴 녹음 파일을 읽어 높이를 내고, 없는 파일은 읽지 못한 쪽으로 표시한다")
    func loadsRecording() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("compare-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioFileAnalyzer.writeM4A(samples: Signal.sine(180, sampleRate: 48_000, count: 48_000 * 2),
                                       sampleRate: 48_000, to: url)

        let player = ComparePlayer()
        await player.load(.a, from: url)
        let loaded = try #require(player.a)
        #expect(abs(loaded.duration - 2) < 0.1)
        #expect(abs(PitchSummary.percentile(loaded.voiced.sorted(), 0.5) - 180) < 1)
        #expect(player.loadingSides.isEmpty)

        await player.load(.b, from: url.deletingLastPathComponent().appendingPathComponent("없는 파일.m4a"))
        #expect(player.b == nil)
        #expect(player.failedSides == [.b])
        #expect(player.playing == nil)
    }
}
