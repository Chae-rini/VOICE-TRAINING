import Testing
@testable import VoicePractice

@MainActor
struct PracticeScriptTests {
    let scripts = PracticeScripts.all

    static let categories: Set = ["대화문", "독백", "수필", "감성 내레이션", "소설", "산문시", "비문학", "음색 교정"]
    static let styles: Set = ["해요체", "합쇼체", "반말", "문어체"]
    static let topics: Set = ["과학", "인문", "사회", "예술", "생활"]
    /// 성별이 드러나는 말. 대본 원칙에 따라 쓰지 않는다.
    static let genderedWords = [
        "엄마", "아빠", "어머니", "아버지", "언니", "오빠", "누나", "고모", "삼촌", "할머니", "할아버지",
        "아저씨", "아주머니", "아줌마", "남편", "아내", "남자", "여자", "그녀", "소년", "소녀", "신랑", "신부",
    ]

    @Test("대본 파일을 읽으면 200편이 나온다")
    func loadsAll() {
        #expect(scripts.count == 200)
    }

    @Test("번호·제목·본문이 겹치지 않는다")
    func unique() {
        #expect(Set(scripts.map(\.id)).count == scripts.count)
        #expect(Set(scripts.map(\.title)).count == scripts.count)
        #expect(Set(scripts.map(\.text)).count == scripts.count)
    }

    @Test("예상 낭독 시간이 10~60초 안이다")
    func lengthsInRange() {
        for script in scripts {
            #expect((10...60).contains(script.estimatedSeconds), "\(script.id) \(script.title): \(script.estimatedSeconds)초")
        }
    }

    @Test("종류·말투·분야 이름이 정해진 값 중 하나다")
    func knownLabels() {
        for script in scripts {
            #expect(Self.categories.contains(script.category), "\(script.id) 종류: \(script.category)")
            #expect(Self.styles.contains(script.style), "\(script.id) 말투: \(script.style)")
            if let topic = script.topic {
                #expect(script.category == "비문학" && Self.topics.contains(topic), "\(script.id) 분야: \(topic)")
            }
        }
    }

    @Test("성별이 드러나는 말과 아라비아 숫자를 쓰지 않는다")
    func followsWritingRules() {
        for script in scripts {
            let found = Self.genderedWords.filter { script.text.contains($0) || script.title.contains($0) }
            #expect(found.isEmpty, "\(script.id) \(script.title): \(found)")
            #expect(!script.text.contains { $0.isASCII && $0.isNumber }, "\(script.id) \(script.title): 숫자")
        }
    }

    @Test("비문학은 모두 사실 확인 표시가 있다")
    func nonfictionIsFlagged() {
        for script in scripts where script.category == "비문학" {
            #expect(script.needsFactCheck == true, "\(script.id) \(script.title)")
        }
    }

    @Test("음색 교정 대본은 목표 모음이 가장 많이 나온다")
    func focusVowelIsMostFrequent() {
        for script in scripts where script.category == "음색 교정" {
            let counts = KoreanVowel.counts(in: script.text)
            let focus = KoreanVowel(rawValue: script.focusVowel ?? "")
            #expect(focus != nil, "\(script.id) 목표 모음 없음")
            if let focus {
                #expect(counts[focus, default: 0] == counts.values.max(), "\(script.id) \(script.title): \(counts)")
            }
        }
    }

    @Test("섞인 순서: 대본마다 한 번씩, 같은 씨앗이면 같은 순서, 씨앗(열 때)마다 첫 대본이 달라진다")
    func shuffledOrder() {
        let order = ScriptOrder.shuffled(count: scripts.count, seed: 42)
        #expect(order.sorted() == Array(0..<scripts.count))
        #expect(order == ScriptOrder.shuffled(count: scripts.count, seed: 42))
        #expect(order != Array(0..<scripts.count), "파일 순서 그대로가 아니다")
        let firsts = Set((0..<50).map { ScriptOrder.shuffled(count: scripts.count, seed: UInt64($0)).first })
        #expect(firsts.count > 30, "열 때마다 다른 대본부터 보여야 한다")
        #expect(ScriptOrder.shuffled(count: 0, seed: 1).isEmpty)
    }
}

@MainActor
struct PitchHistoryTests {
    @Test("꺾은선은 50ms 넘게 벌어진 곳에서만 끊긴다")
    func voicedSegments() {
        var history = PitchHistory()
        history.append(contentsOf: [
            PitchReading(time: 0.000, frequency: 200),
            PitchReading(time: 0.021, frequency: 202),
            PitchReading(time: 0.042, frequency: 204),
            PitchReading(time: 0.064, frequency: nil),  // 점 하나가 빠짐 → 선은 이어진다
            PitchReading(time: 0.085, frequency: 206),
            PitchReading(time: 0.200, frequency: 190),  // 0.115초 무음 → 선이 끊긴다
        ])
        #expect(history.voicedSegments().map(\.count) == [4, 1])
    }
}
