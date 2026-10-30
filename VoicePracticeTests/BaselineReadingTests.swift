import Testing
@testable import VoicePractice

/// ‘내 목소리 재기’에서 읽을 글을 무작위로 고르기 (2026-10-31, 그 전에는 늘 같은 문장 하나).
@MainActor
struct BaselineReadingTests {
    private func script(_ id: String, _ category: String, needsFactCheck: Bool? = nil) -> PracticeScript {
        PracticeScript(id: id, category: category, topic: nil, style: "해요체", title: "제목 \(id)", text: "본문 \(id)",
                       focusVowel: nil, needsFactCheck: needsFactCheck)
    }

    @Test("후보: 내 문장 전부 + 평소 말투에 가까운 대본(대화문·독백·비문학·수필) 중 사실 확인이 끝난 것")
    func candidates() {
        let scripts = [
            script("a", "대화문"), script("b", "독백"), script("c", "수필"),
            script("d", "비문학"), script("e", "비문학", needsFactCheck: true),
            script("f", "소설"), script("g", "산문시"), script("h", "감성 내레이션"), script("i", "음색 교정"),
        ]
        let candidates = BaselineReading.candidates(sentences: ["문장 하나", "문장 둘"], scripts: scripts)
        #expect(candidates.map(\.text) == ["문장 하나", "문장 둘", "본문 a", "본문 b", "본문 c", "본문 d"])
        #expect(candidates.filter(\.isSentence).count == 2)
        #expect(candidates.last?.title == "제목 d")

        // 앱에 든 글: 내 문장 15개 + 대화문 50·독백 30·수필 20 (비문학 40편은 아직 모두 사실 확인 전,
        // 2026-10-31에 더한 발표·면접 답변 등은 ‘평소 목소리’ 재기와 맞지 않아 넣지 않음)
        let bundled = BaselineReading.candidates()
        #expect(bundled.count == PracticeSentences.all.count + 100)
        #expect(bundled.contains(BaselineReading(text: "회의는 오후 두 시에 시작합니다.", title: nil)))
    }

    @Test("무작위로 고르되 바로 앞에 보인 글은 다시 고르지 않는다. 같은 시드면 같은 글")
    func randomExcludesPrevious() {
        let candidates = BaselineReading.candidates()
        var generator = SeededGenerator(seed: 42)
        var previous = BaselineReading.random(from: candidates, using: &generator)
        var seen: Set<String> = [previous.text]
        for _ in 0..<200 {
            let next = BaselineReading.random(excluding: previous, from: candidates, using: &generator)
            #expect(next != previous)
            seen.insert(next.text)
            previous = next
        }
        #expect(seen.count > 50, "여러 글이 고루 나와야 한다")

        var a = SeededGenerator(seed: 7)
        var b = SeededGenerator(seed: 7)
        #expect(BaselineReading.random(from: candidates, using: &a) == BaselineReading.random(from: candidates, using: &b))
    }

    @Test("후보가 하나뿐이면 그것을, 하나도 없으면 예전 문장을 쓴다")
    func smallPools() {
        let only = BaselineReading(text: "하나", title: nil)
        var generator = SeededGenerator(seed: 1)
        #expect(BaselineReading.random(excluding: only, from: [only], using: &generator) == only)
        #expect(BaselineReading.random(from: [], using: &generator) == BaselineReading.fallback)
    }

    @Test("안내 글: 문장은 두세 번, 대본은 처음부터 (다 못 읽어도 괜찮다)")
    func instructions() {
        #expect(BaselineReading(text: "짧은 문장", title: nil).instruction == "10초 동안 이 문장을 평소처럼 두세 번 읽어 주세요.")
        #expect(BaselineReading(text: "긴 대본", title: "제목").instruction
                == "10초 동안 이 대본을 처음부터 평소처럼 읽어 주세요. 다 못 읽어도 괜찮아요.")
    }
}
