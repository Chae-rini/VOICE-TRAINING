import Testing
@testable import VoicePractice

@MainActor
struct SentenceGeneratorTests {
    let generator = SentenceGenerator()

    @Test("받침에 따라 조사를 고른다", arguments: [
        ("친구을(를)", "친구를"),
        ("동생을(를)", "동생을"),
        ("은행이(가)", "은행이"),
        ("버스이(가)", "버스가"),
        ("우유은(는)", "우유는"),
        ("공원은(는)", "공원은"),
        ("책과(와)", "책과"),
        ("우유과(와)", "우유와"),
        ("공원(으)로", "공원으로"),
        ("버스(으)로", "버스로"),
        ("지하철(으)로", "지하철로"),  // ㄹ 받침 뒤에는 "로"
    ])
    func particles(input: String, expected: String) {
        #expect(KoreanParticle.resolve(in: input) == expected)
    }

    @Test("SentencePatterns의 모든 패턴에 오타가 없다")
    func allPatternsAreValid() {
        for pattern in generator.patterns {
            let problems = generator.problems(in: pattern)
            #expect(problems.isEmpty, "\(pattern) → \(problems)")
        }
    }

    @Test("단어 목록: 비어 있지 않고, 한글로 끝나고, 겹치지 않는다")
    func allWordsAreUsable() {
        for (category, words) in generator.words {
            #expect(!words.isEmpty, "{\(category)} 단어가 없어요")
            #expect(Set(words).count == words.count, "{\(category)}에 같은 단어가 두 번 있어요")
            for word in words {
                // 조사를 고르려면 마지막 글자가 한글이어야 한다.
                #expect(word.last.flatMap { KoreanParticle.finalConsonantIndex(of: $0) } != nil, "{\(category)} \(word)")
            }
        }
    }

    @Test("잘못된 패턴은 문제로 알려 준다", arguments: [
        "{없는카테고리}에 [가요|갑니다|가].",
        "{장소에 [가요|갑니다|가].",
        "{장소}에 [가요|갑니다].",
        "{장소}에 가요.",
        "{장소} (으)로 [가요|갑니다|가].",
    ])
    func detectsBrokenPatterns(pattern: String) {
        #expect(!generator.problems(in: pattern).isEmpty)
    }

    @Test("정한 말투의 끝맺음을 쓴다")
    func usesChosenSpeechLevel() {
        var random = SeededGenerator(seed: 1)
        let pattern = "{장소}(으)로 [가요|갑니다|가]."
        #expect(generator.fill(pattern, level: .polite, using: &random).hasSuffix("가요."))
        #expect(generator.fill(pattern, level: .formal, using: &random).hasSuffix("갑니다."))
        #expect(generator.fill(pattern, level: .casual, using: &random).hasSuffix(" 가."))
    }

    @Test("15문장: 중복 없음, 말투 5:5:5, 표시 기호가 남지 않음, 7개 모음이 모두 나옴",
          arguments: [1, 2, 3, 4, 5] as [UInt64])
    func deck(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        let deck = generator.makeDeck(count: 15, using: &random)

        #expect(deck.count == 15)
        #expect(Set(deck.map(\.text)).count == 15)
        for level in SpeechLevel.allCases {
            #expect(deck.filter { $0.level == level }.count == 5)
        }
        for sentence in deck {
            let leftovers = ["{", "}", "[", "]", "|"] + KoreanParticle.markers
            #expect(!leftovers.contains { sentence.text.contains($0) }, "\(sentence.text)")
        }

        var totals: [KoreanVowel: Int] = [:]
        for sentence in deck {
            totals.merge(KoreanVowel.counts(in: sentence.text), uniquingKeysWith: +)
        }
        #expect(KoreanVowel.allCases.allSatisfy { totals[$0, default: 0] > 0 })
    }

    @Test("같은 시드면 같은 문장이 나온다")
    func reproducible() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        #expect(generator.makeDeck(using: &first) == generator.makeDeck(using: &second))
    }
}

@MainActor
struct PracticeDurationTests {
    @Test("10초~3분 안으로 자르고 10초 단위로 맞춘다", arguments: [
        (0.0, 10.0), (5.0, 10.0), (44.0, 40.0), (45.0, 50.0), (999.0, 180.0),
    ])
    func normalized(input: Double, expected: Double) {
        #expect(PracticeDuration.normalized(input) == expected)
    }

    @Test("시간 표시 문구", arguments: [
        (10.0, "10초"), (60.0, "1분"), (90.0, "1분 30초"), (180.0, "3분"),
    ])
    func label(seconds: Double, expected: String) {
        #expect(PracticeDuration.label(for: seconds) == expected)
    }
}
