import Foundation
import SwiftData
import Testing
@testable import VoicePractice

/// AI 앱에서 쓴 대본 가져오기 (2026-10-31, 사용자 요청): 부탁 글, 붙여넣은 글 나누기, 내 대본 저장·지우기.
@MainActor
struct ScriptImportTests {
    @Test("‘제목:’ 줄과 ‘---’ 줄로 여러 편을 나누고, 첫 제목 앞의 인사말은 버린다")
    func parsesTitlesAndSeparators() {
        let pasted = """
        네, 요청하신 대본 두 편을 써 드릴게요!

        제목: 새벽 첫차
        오늘은 첫차를 탔어요. 창밖이 아직 깜깜했지요.
        ---
        **제목:** 우산 빌려주기
        비가 와서 우산을 빌려줬어요.

        다음 날 돌려받았어요.
        """
        #expect(ScriptImport.parse(pasted) == [
            .init(title: "새벽 첫차", text: "오늘은 첫차를 탔어요. 창밖이 아직 깜깜했지요."),
            .init(title: "우산 빌려주기", text: "비가 와서 우산을 빌려줬어요.\n\n다음 날 돌려받았어요."),
        ])
    }

    @Test("여러 모양의 나눔 줄·제목 줄·윈도 줄바꿈, 빈 조각은 건너뛴다")
    func toleratesFormats() {
        let pasted = "## 제목： 하나\r\n본문: 첫째 글이에요.\r\n***\r\n\r\n———\r\nTitle: 둘\r\n둘째 글이에요.\r\n====\r\n"
        #expect(ScriptImport.parse(pasted) == [
            .init(title: "하나", text: "첫째 글이에요."),
            .init(title: "둘", text: "둘째 글이에요."),
        ])
        // 하이픈 두 개나 다른 기호가 섞인 줄은 나눔 줄이 아니다
        #expect(ScriptImport.parse("제목: 셋\n가 -- 나\n-=-\n다").count == 1)
        #expect(ScriptImport.parse("  \n---\n\n").isEmpty)
    }

    @Test("제목이 없으면 첫 문장으로 짓고, 길면 20자에서 자른다")
    func fallbackTitle() {
        #expect(ScriptImport.parse("짧은 첫 문장. 그다음 문장.").first?.title == "짧은 첫 문장")
        let long = ScriptImport.parse("아주 길고 길어서 제목으로 쓰기에는 너무 긴 첫 문장이에요. 끝.").first
        // 20자에서 자른 뒤 끝의 빈칸은 떼고 말줄임표를 붙인다
        #expect(long?.title == "아주 길고 길어서 제목으로 쓰기에는…")
    }

    @Test("한 번에 20편까지, 한 편은 3000자까지")
    func limits() {
        let many = (1...25).map { "제목: \($0)번\n본문 \($0)" }.joined(separator: "\n---\n")
        #expect(ScriptImport.parse(many).count == ScriptImport.maximumDrafts)
        let huge = ScriptImport.parse("제목: 긴 글\n" + String(repeating: "가", count: 5000))
        #expect(huge.first?.text.count == ScriptImport.maximumTextLength)
    }

    @Test("부탁 글: 편 수·길이·말투·주제를 넣고, 울림 대본 규칙과 나누기 쉬운 형식을 부탁한다")
    func prompt() {
        let text = ScriptImport.prompt(.init(count: 2, seconds: 20, style: "합쇼체", topic: "발표 연습"))
        for expected in [
            "한국어 대본을 2편", "약 20초 (한글 약 90자)", "말투: 합쇼체로", "주제: 발표 연습",
            "성별이 드러나는 말", "목에 무리가 가는 장면", "제목: (제목)\n(본문)\n---", "인사말이나 설명 없이",
        ] {
            #expect(text.contains(expected), "\(expected)")
        }
        let free = ScriptImport.prompt(.init())
        #expect(free.contains("3편"))
        #expect(free.contains("자유롭게 섞어서"))
        #expect(free.contains("일상에서 있을 법한 장면"))
        // 부탁 글의 형식대로 쓴 답은 그대로 나뉜다
        let answer = "제목: 하나\n첫째.\n---\n제목: 둘\n둘째."
        #expect(ScriptImport.parse(answer).map(\.title) == ["하나", "둘"])
    }

    @Test("내 대본에 남기고 지운다. 대본 화면에서는 ‘내 대본’ 종류, 말투 없음")
    func savesAndDeletes() throws {
        // deleteAll은 녹음 폴더를 통째로 지우므로 이 시험만 쓰는 폴더를 준다
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = PracticeArchive(inMemory: true, recordingsDirectory: directory)
        try archive.saveImportedScripts([.init(title: "하나", text: "첫째 글이에요."), .init(title: "둘", text: "둘째 글")])
        let saved = try archive.context.fetch(FetchDescriptor<ImportedScript>(sortBy: [SortDescriptor(\.addedAt)]))
        #expect(saved.map(\.title) == ["하나", "둘"], "붙여넣은 순서대로")

        let script = PracticeScript(imported: saved[0])
        #expect(script.category == "내 대본")
        #expect(script.style.isEmpty)
        #expect(script.isImported)
        #expect(!PracticeScripts.all.contains { $0.isImported })
        #expect(script.syllableCount == 6)

        try archive.delete(saved[0])
        #expect(try archive.context.fetch(FetchDescriptor<ImportedScript>()).map(\.title) == ["둘"])
        // ‘모든 기록 지우기’는 내 대본을 지우지 않는다
        try archive.deleteAll()
        #expect(try archive.context.fetchCount(FetchDescriptor<ImportedScript>()) == 1)
    }
}
