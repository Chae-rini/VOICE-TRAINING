import Foundation
import Testing
import UniformTypeIdentifiers
@testable import VoicePractice

/// ‘파일로 저장’(m4a)과 그래프 높이 (2026-10-25)
@MainActor
struct AudioFileExportTests {
    @Test("저장 창에 처음 적을 파일 이름: Ullim-날짜-시각")
    func defaultFileName() throws {
        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20, minute: 12)))
        #expect(AudioFileDocument.defaultFileName(for: date, timeZone: seoul) == "Ullim-20261025-2012")
    }

    @Test("저장 창이 붙이는 확장자는 .m4a다 (mpeg4Audio로 두면 .mp4가 붙었다)")
    func fileExtension() {
        #expect(AudioFileDocument.contentType.preferredFilenameExtension == "m4a")
        #expect(AudioFileDocument.contentType.conforms(to: .audio))
    }

    @Test("마지막 녹음을 m4a로 만들고, 다시 재도 같은 높이이며, 저장 창에 넘길 내용이 파일과 같다. 지난번 임시 파일은 지운다")
    func lastTakeM4A() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("source-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: source) }
        try AudioFileAnalyzer.writeM4A(samples: Signal.sine(190, sampleRate: 48_000, count: 48_000 * 2), sampleRate: 48_000, to: source)

        let audio = AudioInputManager(archive: PracticeArchive(inMemory: true, recordingsDirectory: directory))
        #expect(await audio.importRecording(from: source, title: "합성음"))
        audio.stop()

        let first = try await audio.makeLastTakeM4A()
        #expect(first.pathExtension == "m4a")
        #expect(AudioInputManager.isExportFile(named: first.lastPathComponent))
        let reread = try AudioFileAnalyzer.analyze(url: first)
        let summary = try #require(PitchSummary(readings: reread.readings, duration: reread.duration, target: nil))
        #expect(abs(summary.median - 190) < 1)
        #expect(abs(reread.duration - 2) < 0.1)

        let document = try AudioFileDocument(url: first)
        #expect(document.data == (try Data(contentsOf: first)))
        #expect(!document.data.isEmpty)

        // 다음에 만들면 지난번 임시 파일은 지운다 (임시 폴더에 쌓이지 않게)
        try await Task.sleep(for: .seconds(1.1))  // 파일 이름이 초 단위라 겹치지 않게
        let second = try await audio.makeLastTakeM4A()
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: first.path))
        try? FileManager.default.removeItem(at: second)
    }

    @Test("녹음이 없으면 m4a를 만들지 않고 오류를 던진다")
    func noTake() async {
        let audio = AudioInputManager(archive: PracticeArchive(inMemory: true, recordingsDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)")))
        await #expect(throws: (any Error).self) { try await audio.makeLastTakeM4A() }
    }

    @Test("그래프 높이: 쓸 수 있는 화면 높이의 45%(대본 읽기 33%), 작은 화면에서도 220·150pt 이상, 큰 화면에서도 380·280pt 이하")
    func graphHeight() {
        #expect(abs(PitchGraphView.graphHeight(available: 600, isCompact: false) - 270) < 1e-9)
        #expect(abs(PitchGraphView.graphHeight(available: 600, isCompact: true) - 198) < 1e-9)
        #expect(PitchGraphView.graphHeight(available: 300, isCompact: false) == 220)
        #expect(PitchGraphView.graphHeight(available: 300, isCompact: true) == 150)
        #expect(PitchGraphView.graphHeight(available: 1200, isCompact: false) == 380)
        #expect(PitchGraphView.graphHeight(available: 1200, isCompact: true) == 280)
    }
}
