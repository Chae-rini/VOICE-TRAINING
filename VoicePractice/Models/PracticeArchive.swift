import Foundation
import SwiftData

/// 연습 기록을 기기 안에 저장하는 곳. 숫자는 SwiftData에, 직접 남긴 녹음의 소리는 Documents/Recordings에 m4a로 둔다.
/// 네트워크로는 아무것도 보내지 않는다 (원칙 2).
/// 녹음 소리는 목소리라는 민감한 정보라서 iOS 백업(iCloud 포함)에서 뺀다. 숫자 기록은 iOS 백업 설정을 따른다.
@MainActor
final class PracticeArchive {
    /// 앱 전체가 함께 쓰는 저장소
    static let shared = PracticeArchive()

    static let models: [any PersistentModel.Type] = [
        PracticeSession.self, SavedRecording.self, BaselineRecord.self, VowelRecord.self,
    ]

    let container: ModelContainer
    /// 녹음 소리 파일을 두는 폴더
    let recordingsDirectory: URL
    /// 저장소를 열지 못해 이번 실행 동안만 메모리에 기록하는지
    let isTemporary: Bool

    /// `inMemory`와 `recordingsDirectory`는 테스트용이다 (앱의 실제 기록을 건드리지 않게).
    init(inMemory: Bool = false, recordingsDirectory: URL? = nil) {
        let schema = Schema(Self.models)
        if let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)) {
            self.container = container
            isTemporary = inMemory
        } else {
            // 저장소 파일을 열지 못해도 앱은 쓸 수 있게, 이번 실행 동안만 메모리에 둔다.
            // 메모리 저장소는 파일을 쓰지 않으므로 만들기에 실패하지 않는다.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            isTemporary = true
        }
        self.recordingsDirectory = recordingsDirectory
            ?? URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    var context: ModelContext {
        container.mainContext
    }

    // MARK: - 남기기

    /// 연습 한 번의 요약을 남긴다 (정지할 때 자동으로).
    func saveSession(_ summary: PracticeSessionLog.Summary) {
        context.insert(PracticeSession(summary))
        save()
    }

    /// ‘내 목소리 재기’ 결과를 이력에 더한다 (저장을 눌렀을 때).
    func saveBaseline(_ baseline: VoiceBaseline, measuredAt: Date = .now) {
        context.insert(BaselineRecord(baseline, measuredAt: measuredAt))
        save()
    }

    /// 모음 하나를 잰 결과를 이력에 더한다.
    func saveVowel(_ entry: VowelMap.Entry, for vowel: KoreanVowel) {
        context.insert(VowelRecord(entry, vowel: vowel))
        save()
    }

    /// 녹음 소리를 m4a로 저장하고 기록을 남긴다. 파일 만들기는 화면이 멈추지 않게 백그라운드에서 한다.
    @discardableResult
    func saveRecording(samples: [Float], sampleRate: Double, summary: PitchSummary, title: String, memo: String,
                       language: PracticeLanguage, recordedAt: Date) async throws -> SavedRecording {
        try prepareRecordingsDirectory()
        let fileName = "\(UUID().uuidString).m4a"
        let url = recordingsDirectory.appending(path: fileName)
        try await Task.detached(priority: .userInitiated) {
            try AudioFileAnalyzer.writeM4A(samples: samples, sampleRate: sampleRate, to: url)
        }.value
        Self.excludeFromBackup(url)

        let recording = SavedRecording(summary: summary, title: title, memo: memo, fileName: fileName,
                                       language: language, recordedAt: recordedAt)
        context.insert(recording)
        save()
        return recording
    }

    func fileURL(for recording: SavedRecording) -> URL {
        recordingsDirectory.appending(path: recording.fileName)
    }

    // MARK: - 지우기

    /// 남긴 녹음 하나를 소리 파일과 함께 지운다.
    func delete(_ recording: SavedRecording) {
        try? FileManager.default.removeItem(at: fileURL(for: recording))
        context.delete(recording)
        save()
    }

    /// 모든 기록과 녹음 파일을 지운다. 지금 쓰는 기준 목소리·목표 범위·모음 지도(UserDefaults)는 그대로 둔다.
    func deleteAll() throws {
        try context.delete(model: PracticeSession.self)
        try context.delete(model: SavedRecording.self)
        try context.delete(model: BaselineRecord.self)
        try context.delete(model: VowelRecord.self)
        try context.save()
        if FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            try FileManager.default.removeItem(at: recordingsDirectory)
        }
    }

    // MARK: - 내부

    /// 메인 저장소(mainContext)는 때가 되면 스스로도 저장하지만, 앱이 곧 꺼질 수 있으니 바로 저장한다.
    private func save() {
        try? context.save()
    }

    private func prepareRecordingsDirectory() throws {
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        Self.excludeFromBackup(recordingsDirectory)
    }

    /// iOS 백업(iCloud·컴퓨터)에 넣지 않게 표시한다. 기기를 바꾸면 이 파일은 옮겨지지 않는다.
    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
