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
        PracticeSession.self, PracticeTake.self, SavedRecording.self, BaselineRecord.self, VowelRecord.self,
        ImportedScript.self,
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
    // 남기기·지우기는 영구 저장까지 마쳐야 끝난다. 저장에 실패하면 바꾼 내용을 되돌리고 오류를 호출한 쪽에 던진다
    // (화면이 "남겼어요"를 보여 주지 않게).

    /// 연습 한 번의 요약을 녹음마다의 요약과 함께 남긴다 (정지할 때 자동으로).
    func saveSession(_ summary: PracticeSessionLog.Summary) throws {
        let session = PracticeSession(summary)
        context.insert(session)
        // 둘 다 저장소에 넣은 뒤에 잇는다. 넣기 전에 잇는 방식은 SwiftData에서 문제가 있었다는 보고가 있어 피했다 (직접 재현하지는 않음).
        for take in summary.takes {
            let record = PracticeTake(take)
            context.insert(record)
            record.session = session
        }
        try save()
    }

    /// ‘내 목소리 재기’ 결과를 이력에 더한다 (저장을 눌렀을 때).
    func saveBaseline(_ baseline: VoiceBaseline, measuredAt: Date = .now) throws {
        context.insert(BaselineRecord(baseline, measuredAt: measuredAt))
        try save()
    }

    /// 모음 하나를 잰 결과를 이력에 더한다.
    func saveVowel(_ entry: VowelMap.Entry, for vowel: KoreanVowel) throws {
        context.insert(VowelRecord(entry, vowel: vowel))
        try save()
    }

    /// 녹음 소리를 m4a로 저장하고 기록을 남긴다. 파일 만들기는 화면이 멈추지 않게 백그라운드에서 한다.
    /// 파일을 만든 뒤 기록 저장에 실패하면 그 파일을 지워, 소리만 있거나 기록만 있는 반쪽 기록이 남지 않게 한다.
    @discardableResult
    /// `phraseEndings`: 그 녹음의 문장 끝 분석 숫자 (요약 카드와 같은 값, 2026-10-30~).
    func saveRecording(samples: [Float], sampleRate: Double, summary: PitchSummary, title: String, memo: String,
                       language: PracticeLanguage, recordedAt: Date, f2Median: Double? = nil,
                       phraseEndings: PhraseEndingSummary? = nil) async throws -> SavedRecording {
        try prepareRecordingsDirectory()
        let fileName = "\(UUID().uuidString).m4a"
        let url = recordingsDirectory.appending(path: fileName)
        try await Task.detached(priority: .userInitiated) {
            try AudioFileAnalyzer.writeM4A(samples: samples, sampleRate: sampleRate, to: url)
        }.value
        Self.excludeFromBackup(url)

        let recording = SavedRecording(summary: summary, title: title, memo: memo, fileName: fileName,
                                       language: language, recordedAt: recordedAt, f2Median: f2Median,
                                       phraseEndings: phraseEndings)
        context.insert(recording)
        do {
            try save()
        } catch {
            try? FileManager.default.removeItem(at: url)  // 지우기에 실패해도 원래 오류를 알리는 것이 먼저다
            throw error
        }
        return recording
    }

    /// 그 녹음 기록이 아직 저장소에 있는지 ([기록] 탭에서 지웠는지 확인할 때).
    func recordingExists(_ id: PersistentIdentifier) -> Bool {
        var descriptor = FetchDescriptor<SavedRecording>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        // 읽기에 실패하면 없는 것으로 본다 (다시 남길 수 있게 두는 쪽을 고른다).
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    func fileURL(for recording: SavedRecording) -> URL {
        recordingsDirectory.appending(path: recording.fileName)
    }

    /// 그날 연습 기록이 남았는지 (연습 알림을 건너뛸지 정할 때). 자정을 넘겨 끝난 연습은 끝난 날에도 연습한 것으로 본다.
    func hasPractice(on date: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.endedAt >= start && $0.startedAt < end }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    // MARK: - 지우기

    /// 남긴 녹음 하나를 소리 파일과 함께 지운다. 기록을 먼저 지우고 저장에 성공한 뒤에 파일을 지운다
    /// (저장에 실패하면 기록이 되돌아오는데, 그때 파일이 없으면 반쪽 기록이 되므로).
    func delete(_ recording: SavedRecording) throws {
        let url = fileURL(for: recording)
        context.delete(recording)
        try save()
        try? FileManager.default.removeItem(at: url)  // 기록은 이미 지워졌다. 파일이 남아도 화면에는 보이지 않는다
    }

    /// 연습 기록 하나를 녹음마다의 요약과 함께 지운다.
    /// 지우기 규칙(cascade)도 걸어 두었지만, 그것에만 기대지 않고 직접 지운다.
    func delete(_ session: PracticeSession) throws {
        for take in session.takes {
            context.delete(take)
        }
        context.delete(session)
        try save()
    }

    func delete(_ baseline: BaselineRecord) throws {
        context.delete(baseline)
        try save()
    }

    // MARK: - 내 대본 (AI 앱 등에서 가져온 대본, 2026-10-31~)

    /// 가져온 대본을 ‘내 대본’에 더한다 (가져오기 화면에서 저장을 눌렀을 때). 붙여넣은 순서대로 남게 시각을 조금씩 다르게 둔다
    func saveImportedScripts(_ drafts: [ScriptImport.Draft], addedAt: Date = .now) throws {
        for (offset, draft) in drafts.enumerated() {
            context.insert(ImportedScript(title: draft.title, text: draft.text,
                                          addedAt: addedAt.addingTimeInterval(Double(offset) / 1000)))
        }
        try save()
    }

    func delete(_ script: ImportedScript) throws {
        context.delete(script)
        try save()
    }

    /// 모든 기록과 녹음 파일을 지운다. 지금 쓰는 기준 목소리·목표 범위·모음 지도(UserDefaults)와 내 대본은 그대로 둔다.
    /// 한꺼번에 지우는 `delete(model:)`은 화면의 목록(@Query)이 바로 따라 바뀌지 않는다는 보고가 있어 하나씩 지운다.
    func deleteAll() throws {
        try deleteEach(PracticeTake.self)
        try deleteEach(PracticeSession.self)
        try deleteEach(SavedRecording.self)
        try deleteEach(BaselineRecord.self)
        try deleteEach(VowelRecord.self)
        try save()
        if FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            try FileManager.default.removeItem(at: recordingsDirectory)
        }
    }

    // MARK: - 내부

    private func deleteEach<T: PersistentModel>(_ type: T.Type) throws {
        for record in try context.fetch(FetchDescriptor<T>()) {
            context.delete(record)
        }
    }

    #if DEBUG
    /// 테스트에서 저장 실패를 흉내 낼 때만 쓴다. 실제 앱에서는 늘 nil이다.
    var simulatedSaveError: (any Error)?
    #endif

    /// 바뀐 내용을 바로 영구 저장한다 (메인 저장소는 때가 되면 스스로도 저장하지만, 앱이 곧 꺼질 수 있으므로).
    /// 실패하면 아직 저장하지 않은 바뀐 내용을 모두 되돌리고 오류를 던진다. 되돌리지 않으면 화면 목록에는
    /// 저장 안 된 기록이 보이고, 나중에 저절로 저장될 수도 있다. 화면에서 메모 등을 고친 뒤에도 부른다.
    func save() throws {
        do {
            #if DEBUG
            if let simulatedSaveError { throw simulatedSaveError }
            #endif
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
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
