import Foundation
import SwiftData

/// AI 앱에서 쓴 대본을 울림으로 가져오기 (2026-10-31~, 사용자 요청). 앱은 인터넷에 연결하지 않으므로(원칙 2),
/// ① 울림이 부탁 글을 만들면 사용자가 고른 AI 앱으로 보내고(공유 창·복사) ② AI가 쓴 답을 사용자가 복사해 와 붙여넣는다.
/// 붙여넣은 글은 ‘제목:’ 줄과 ‘---’ 줄로 나눠 대본 여러 편으로 만든다 (부탁 글이 이 형식을 부탁한다).
enum ScriptImport {
    /// 붙여넣은 글에서 나온 대본 한 편 (저장 전, 미리 보기에서 제목을 고칠 수 있다)
    struct Draft: Equatable {
        var title: String
        var text: String
    }

    /// 한 번에 가져오는 최대 편 수
    static let maximumDrafts = 20
    /// [글자] 한 편 본문의 최대 길이. 넘으면 자른다 (실수로 아주 긴 글을 붙여넣었을 때)
    static let maximumTextLength = 3000
    /// [글자] 제목이 없어 첫 문장으로 지을 때의 최대 길이
    static let fallbackTitleLength = 20

    /// 붙여넣은 글을 대본들로 나눈다.
    /// - ‘---’처럼 같은 기호(-, —, =, *, _)만 세 개 넘게 있는 줄에서 나눈다.
    /// - ‘제목:’ 줄(앞의 #·** 같은 꾸밈은 무시)이 있으면 제목으로 쓰고, 그 앞의 줄(“네, 대본을 써 드릴게요” 같은 인사)은 버린다.
    /// - 제목이 없으면 본문의 첫 문장으로 제목을 짓는다. 본문 맨 앞의 ‘본문:’은 뗀다.
    static func parse(_ pasted: String) -> [Draft] {
        let lines = pasted.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var chunks: [[String]] = [[]]
        for line in lines {
            if isSeparator(line) {
                chunks.append([])
            } else {
                chunks[chunks.count - 1].append(line)
            }
        }
        return Array(chunks.compactMap { draft(from: $0) }.prefix(maximumDrafts))
    }

    private static func isSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, let first = trimmed.first, "-—=*_".contains(first) else { return false }
        return trimmed.allSatisfy { $0 == first }
    }

    /// 줄 앞뒤의 마크다운 꾸밈(#, **, __)을 뗀다
    private static func plain(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// "제목: 이웃의 인사" → "이웃의 인사". 제목 줄이 아니면 nil
    private static func titleValue(_ line: String) -> String? {
        let text = plain(line)
        for label in ["제목", "title", "Title"] where text.hasPrefix(label) {
            let rest = text.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
            guard let colon = rest.first, colon == ":" || colon == "：" else { continue }
            let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func draft(from chunk: [String]) -> Draft? {
        var lines = chunk
        var title: String?
        if let titleIndex = lines.firstIndex(where: { titleValue($0) != nil }) {
            title = titleValue(lines[titleIndex])
            lines.removeFirst(titleIndex + 1)  // 제목 앞의 인사말까지 버린다
        }
        var body = lines.map { plain($0) }.joined(separator: "\n")
        // 빈 줄이 여러 개면 하나로
        while body.contains("\n\n\n") {
            body = body.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["본문:", "본문 :"] where body.hasPrefix(label) {
            body = body.dropFirst(label.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !body.isEmpty else { return nil }
        if body.count > maximumTextLength {
            body = String(body.prefix(maximumTextLength))
        }
        return Draft(title: title ?? fallbackTitle(for: body), text: body)
    }

    /// 첫 문장(마침표·물음표·느낌표·줄바꿈까지)을 20자까지
    private static func fallbackTitle(for body: String) -> String {
        let firstSentence = body.prefix { !".?!。\n".contains($0) }
        let title = firstSentence.trimmingCharacters(in: .whitespaces)
        guard title.count > fallbackTitleLength else { return title }
        return title.prefix(fallbackTitleLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - AI에게 보낼 부탁 글

    /// 부탁 글에 넣는 조건. 고른 대로 글이 바뀐다
    struct Request: Equatable {
        /// 편 수 (1~5)
        var count = 3
        /// [s] 한 편을 소리 내어 읽는 시간 (20·40·60)
        var seconds = 40
        /// nil이면 말투를 섞어서
        var style: String? = nil
        /// 비우면 일상에서 있을 법한 장면으로
        var topic = ""
    }

    static let countRange = 1...5
    static let secondsOptions = [20, 40, 60]
    static let styleOptions = ["해요체", "합쇼체", "반말", "문어체"]

    /// AI 앱에 보낼 부탁 글. 울림 대본과 같은 규칙(성별이 드러나는 말 쓰지 않기, 목에 무리 가는 장면 빼기)을 부탁하고,
    /// 붙여넣을 때 나누기 쉬운 형식(‘제목:’ 줄, ‘---’ 줄)을 정해 준다.
    static func prompt(_ request: Request) -> String {
        let syllables = Int((Double(request.seconds) * PracticeScript.syllablesPerSecond).rounded())
        let style = request.style.map { "\($0)로" } ?? "해요체·합쇼체·반말 등을 자유롭게 섞어서"
        let topic = request.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        [울림 · 낭독 대본 부탁]
        보이스 트레이닝 앱 ‘울림’에서 소리 내어 읽으며 목소리를 연습할 한국어 대본을 \(request.count)편 써 주세요.

        - 길이: 한 편을 소리 내어 읽으면 약 \(request.seconds)초 (한글 약 \(syllables)자)
        - 말투: \(style)
        - 주제: \(topic.isEmpty ? "일상에서 있을 법한 장면으로 자유롭게" : topic)
        - 성별이 드러나는 말(엄마, 언니, 남자, 그녀 등)은 쓰지 말아 주세요.
        - 소리를 지르거나 목에 무리가 가는 장면, 무거운 주제는 빼 주세요.
        - 실제 사람이나 회사 이름은 쓰지 말아 주세요.

        형식 (그대로 지켜 주세요):
        제목: (제목)
        (본문)
        ---
        제목: (제목)
        (본문)

        인사말이나 설명 없이 대본만 써 주세요.
        """
    }
}

/// 가져와 남긴 내 대본 (2026-10-31~). [높이] 대본 화면에 ‘내 대본’ 종류로 보인다.
/// ‘모든 기록 지우기’로는 지우지 않는다 (연습 기록이 아니라 내가 모은 대본이라서). 대본 화면에서 하나씩 지운다.
@Model
final class ImportedScript {
    var id: UUID
    var title: String
    var text: String
    var addedAt: Date

    init(title: String, text: String, addedAt: Date = .now) {
        id = UUID()
        self.title = title
        self.text = text
        self.addedAt = addedAt
    }

    /// 대본 화면의 종류 이름
    static let category = "내 대본"
    /// 대본 화면에서 쓰는 번호의 머리 (앱에 든 대본 s001~과 겹치지 않게)
    static let idPrefix = "my-"
}

extension PracticeScript {
    /// 가져온 대본을 대본 화면에서 쓰는 모양으로 (말투는 알 수 없어 비워 둔다)
    init(imported: ImportedScript) {
        self.init(id: ImportedScript.idPrefix + imported.id.uuidString, category: ImportedScript.category, topic: nil,
                  style: "", title: imported.title, text: imported.text, focusVowel: nil, needsFactCheck: nil)
    }

    var isImported: Bool {
        id.hasPrefix(ImportedScript.idPrefix)
    }
}
