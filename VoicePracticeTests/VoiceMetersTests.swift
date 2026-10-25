import Foundation
import SwiftData
import Testing
@testable import VoicePractice

/// [높이] 탭의 음량 막대와 공명 밝기 막대 (2026-10-25)
@MainActor
struct VoiceMetersTests {
    /// 0.02초 간격의 점. `level` [dBFS], `f2` [Hz] (nil이면 무음 — 목소리·포먼트 없음)
    private func readings(from start: TimeInterval, seconds: Double, level: Double = -30, f0: Double = 160,
                          f1: Double = 600, f2: Double? = 1500) -> [PitchReading] {
        (0..<Int(seconds / 0.02)).map { index in
            let formants = f2.map {
                FormantAnalyzer.Estimate(f1: Formant(frequency: f1, bandwidth: 80), f2: Formant(frequency: $0, bandwidth: 120))
            }
            return PitchReading(time: start + Double(index) * 0.02, frequency: f2 == nil ? nil : f0,
                                formants: formants, level: level)
        }
    }

    // MARK: - 음량

    @Test("소리 크기: 20·log₁₀(RMS) dBFS, 무음은 바닥값")
    func dBFS() {
        #expect(abs(LevelMeter.dBFS(rms: 1)) < 1e-12)
        #expect(abs(LevelMeter.dBFS(rms: 0.1) + 20) < 1e-9)
        #expect(LevelMeter.dBFS(rms: 0) == LevelMeter.floor)
        // 실제 조각: 진폭 0.5 사인파의 RMS는 0.5/√2 → 약 −9 dBFS
        let frame = Signal.sine(200, sampleRate: 48_000, count: 2048, amplitude: 0.5)
        let rms = sqrt(frame.map { Double($0 * $0) }.reduce(0, +) / Double(frame.count))
        #expect(abs(LevelMeter.dBFS(rms: rms) - 20 * log10(0.5 / sqrt(2))) < 0.1)
    }

    @Test("평활: 최근 0.3초를 세기로 평균한다 (dB로 평균하지 않는다)")
    func smoothing() throws {
        // 1초 동안 −40 dBFS, 그 뒤 0.3초 −20 dBFS → 지금은 −20 쪽만
        let quietThenLoud = readings(from: 0, seconds: 1, level: -40) + readings(from: 1, seconds: 0.3, level: -20)
        let now = try #require(quietThenLoud.last?.time)
        #expect(abs((LevelMeter.smoothedLevel(quietThenLoud, at: now) ?? 0) + 20) < 1e-9)

        // 0.3초 안에 −20과 −40이 반씩: 세기 평균 = 10·log₁₀((0.01 + 0.0001)/2) ≈ −22.97 (dB 평균이면 −30)
        let mixed = (0..<14).map { PitchReading(time: Double($0) * 0.02, frequency: 150, level: $0.isMultiple(of: 2) ? -20 : -40) }
        let level = try #require(LevelMeter.smoothedLevel(mixed, at: 0.26))
        #expect(abs(level - 10 * log10((0.01 + 0.0001) / 2)) < 1e-9)

        #expect(LevelMeter.smoothedLevel([PitchReading](), at: 5) == nil)
        #expect(LevelMeter.position(-60) == 0)
        #expect(LevelMeter.position(-30) == 0.5)
        #expect(LevelMeter.position(5) == 1)
    }

    @Test("아주 큰 소리가 3초 이어질 때만 안내한다 (짧게 크거나, 중간에 많이 작아지면 아님)")
    func sustainedLoud() {
        let loud3 = readings(from: 0, seconds: 3.1, level: -5)
        #expect(LevelMeter.isSustainedLoud(loud3, at: 3.08))

        let loud2 = readings(from: 0, seconds: 2, level: -5)
        #expect(!LevelMeter.isSustainedLoud(loud2, at: 1.98))

        // 3초 중 0.3초(10%) 숨 쉬는 틈은 봐준다
        let withBreath = readings(from: 0, seconds: 1.5, level: -5) + readings(from: 1.5, seconds: 0.3, level: -45)
            + readings(from: 1.8, seconds: 1.3, level: -5)
        #expect(LevelMeter.isSustainedLoud(withBreath, at: 3.08))

        // 3초 중 1초(33%) 작으면 아니다
        let mostlyLoud = readings(from: 0, seconds: 1, level: -5) + readings(from: 1, seconds: 1, level: -30)
            + readings(from: 2, seconds: 1.1, level: -5)
        #expect(!LevelMeter.isSustainedLoud(mostlyLoud, at: 3.08))

        // 보통 크기
        #expect(!LevelMeter.isSustainedLoud(readings(from: 0, seconds: 5, level: -25), at: 4.98))
    }

    // MARK: - 공명 밝기

    @Test("F2 이동 중앙값: 최근 2.5초의 목소리만, 점이 20개보다 적거나 무음이 길면 보여 주지 않는다")
    func resonanceWindow() throws {
        // 3초 동안 F2 1200 Hz(아), 이어서 3초 2300 Hz(이) → 지금은 2300
        let vowels = readings(from: 0, seconds: 3, f2: 1200) + readings(from: 3, seconds: 3, f2: 2300)
        #expect(try #require(ResonanceMeter.current(vowels, at: 5.98)).f2 == 2300)
        // 바뀐 지 1초: 2.5초 창 안에 1200이 1.5초, 2300이 1초 → 중앙값은 1200 쪽
        #expect(try #require(ResonanceMeter.current(vowels, at: 3.98)).f2 == 1200)

        // 점 부족: 목소리 0.3초(15점)뿐
        #expect(ResonanceMeter.current(readings(from: 0, seconds: 0.3), at: 0.28) == nil)
        // 무음 구간: 목소리가 끊긴 지 2.5초가 넘으면 없음
        let thenSilent = readings(from: 0, seconds: 2) + readings(from: 2, seconds: 3, f2: nil)
        #expect(ResonanceMeter.current(thenSilent, at: 4.98) == nil)
        // 무음이 섞여도 목소리 점이 충분하면 그 점들로
        let pauses = readings(from: 0, seconds: 1, f2: 1800) + readings(from: 1, seconds: 0.5, f2: nil)
            + readings(from: 1.5, seconds: 1, f2: 1800)
        #expect(try #require(ResonanceMeter.current(pauses, at: 2.48)).f2 == 1800)
    }

    @Test("목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있으면 불확실로 표시한다 (모음 지도와 같은 규칙)")
    func resonanceUncertain() throws {
        #expect(try #require(ResonanceMeter.current(readings(from: 0, seconds: 1, f0: 150, f1: 300), at: 0.98)).isUncertain == false)
        #expect(try #require(ResonanceMeter.current(readings(from: 0, seconds: 1, f0: 250, f1: 400), at: 0.98)).isUncertain)
    }

    @Test("기준 대비 위치: 기준이 가운데, 반음 6개 밝으면 오른쪽 끝, 넘으면 끝에 붙는다")
    func resonancePosition() {
        #expect(ResonanceMeter.position(f2: 1500, baseline: 1500) == 0.5)
        #expect(abs(ResonanceMeter.position(f2: PitchScale.frequency(1500, offsetBy: 6), baseline: 1500) - 1) < 1e-12)
        #expect(abs(ResonanceMeter.position(f2: PitchScale.frequency(1500, offsetBy: -3), baseline: 1500) - 0.25) < 1e-12)
        #expect(ResonanceMeter.position(f2: 600, baseline: 1500) == 0)
        // 반음 눈금이라 기준이 달라도 같은 비율이면 같은 위치
        #expect(abs(ResonanceMeter.position(f2: 1800, baseline: 1500) - ResonanceMeter.position(f2: 2400, baseline: 2000)) < 1e-12)
    }

    // MARK: - 저장

    @Test("기준 목소리를 잴 때 F2 중앙값도 재고, 저장했다가 다시 읽는다 (못 재면 예전 F2를 지운다)")
    func baselineF2() throws {
        guard case .measured(let baseline) = VoiceBaseline.measure(readings(from: 0, seconds: 3, f2: 1650)) else {
            Issue.record("기준을 재지 못했다")
            return
        }
        #expect(baseline.f2 == 1650)

        let defaults = try #require(UserDefaults(suiteName: "baselineF2-\(UUID().uuidString)"))
        TargetRangeStore.save(baseline, applyingTarget: false, in: defaults)
        #expect(TargetRangeStore.savedBaseline(in: defaults)?.f2 == 1650)

        TargetRangeStore.save(VoiceBaseline(median: 150, low: 130, high: 175), applyingTarget: false, in: defaults)
        #expect(TargetRangeStore.savedBaseline(in: defaults)?.f2 == nil)

        // 포먼트가 거의 없으면 F2 없이 잰다
        let pitchOnly = (0..<150).map { PitchReading(time: Double($0) * 0.02, frequency: 160) }
        guard case .measured(let noF2) = VoiceBaseline.measure(pitchOnly) else {
            Issue.record("기준을 재지 못했다")
            return
        }
        #expect(noF2.f2 == nil)
    }

    @Test("녹음 묶음·연습 기록·남긴 녹음·기준 이력에 F2 중앙값을 저장한다")
    func storesF2() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meters-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = PracticeArchive(inMemory: true, recordingsDirectory: directory)

        // 연습 기록: 앞 20초 F2 1400, 뒤 20초 F2 2000 → 중앙값은 둘 사이
        var log = PracticeSessionLog(startedAt: Date(timeIntervalSince1970: 1_800_000_000), language: .korean)
        log.beginTake()
        log.add(readings(from: 0, seconds: 20, f2: 1400) + readings(from: 20, seconds: 21, f2: 2000))
        let summary = try #require(log.finish(at: Date(timeIntervalSince1970: 1_800_000_060), target: nil))
        #expect(summary.f2Median == 2000)
        try archive.saveSession(summary)
        let session = try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(session.f2MedianHz == 2000)
        #expect(session.summary.f2Median == 2000)

        // 녹음 묶음 → 남긴 녹음
        let samples = [Float](repeating: 0.1, count: 48_000 * 2)
        let playback = try #require(TakeRecorder.makePlaybackBuffer(samples: samples, sampleRate: 48_000))
        let take = RecordedTake(buffer: playback.buffer, startTime: 0, playbackGain: playback.gain, title: "방금 녹음",
                                archiveTitle: "", language: .korean, readings: readings(from: 0, seconds: 2, f2: 1750))
        #expect(take.f2Median == 1750)
        let pitch = try #require(take.summary(target: nil))
        let saved = try await archive.saveRecording(samples: samples, sampleRate: 48_000, summary: pitch, title: "", memo: "",
                                                    language: .korean, recordedAt: .now, f2Median: take.f2Median)
        #expect(saved.f2MedianHz == 1750)

        // 기준 이력
        try archive.saveBaseline(VoiceBaseline(median: 160, low: 140, high: 180, f2: 1600))
        #expect(try #require(try archive.context.fetch(FetchDescriptor<BaselineRecord>()).first).f2MedianHz == 1600)
    }
}
