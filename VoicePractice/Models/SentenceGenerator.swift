import Foundation

/// 말투. 패턴의 `[해요체|합쇼체|반말]` 중 몇 번째를 쓸지 정한다.
enum SpeechLevel: Int, CaseIterable {
    case polite   // 해요체: ~요
    case formal   // 합쇼체: ~습니다, ~습니까
    case casual   // 반말
}

struct GeneratedSentence: Equatable {
    let text: String
    let level: SpeechLevel
}

/// SentencePatterns의 패턴을 단어로 채워 연습 문장을 만든다. 모두 기기 안에서 규칙대로 만든다.
struct SentenceGenerator {
    let patterns: [String]
    let words: [String: [String]]

    /// 문장 한 자리에 후보를 몇 개 만들어 보고 그중 모음 균형이 가장 좋은 것을 고를지.
    private let candidatesPerSentence = 12

    init(patterns: [String] = SentencePatterns.patterns, words: [String: [String]] = SentencePatterns.words) {
        self.patterns = patterns
        self.words = words
    }

    /// `count`개 문장을 만든다.
    /// - 같은 문장은 넣지 않고, 패턴을 다 쓰기 전에는 같은 패턴을 다시 쓰지 않는다.
    /// - 해요체·합쇼체·반말을 돌아가며 배정해 고르게 섞는다.
    /// - 자리마다 후보 여러 개 중 7개 단모음이 가장 고르게 쌓이는 문장을 고른다.
    func makeDeck(count: Int = 15, using generator: inout some RandomNumberGenerator) -> [GeneratedSentence] {
        let levels = (0..<count)
            .map { SpeechLevel.allCases[$0 % SpeechLevel.allCases.count] }
            .shuffled(using: &generator)

        var deck: [GeneratedSentence] = []
        var vowelTotals: [KoreanVowel: Int] = [:]
        var unusedPatterns: [String] = []

        for level in levels {
            if unusedPatterns.isEmpty {
                unusedPatterns = patterns
            }

            var best: (text: String, patternIndex: Int, score: Double)?
            for _ in 0..<candidatesPerSentence {
                guard let patternIndex = unusedPatterns.indices.randomElement(using: &generator) else { break }
                let text = fill(unusedPatterns[patternIndex], level: level, using: &generator)
                guard !deck.contains(where: { $0.text == text }) else { continue }

                let totals = vowelTotals.merging(KoreanVowel.counts(in: text), uniquingKeysWith: +)
                let score = Self.vowelImbalance(totals)
                if let current = best, current.score <= score { continue }
                best = (text, patternIndex, score)
            }

            guard let best else { continue }
            deck.append(GeneratedSentence(text: best.text, level: level))
            vowelTotals.merge(KoreanVowel.counts(in: best.text), uniquingKeysWith: +)
            unusedPatterns.remove(at: best.patternIndex)
        }
        return deck
    }

    /// 패턴 하나를 정해진 말투로 채운다.
    func fill(_ pattern: String, level: SpeechLevel, using generator: inout some RandomNumberGenerator) -> String {
        var text = ""
        var usedWords: Set<String> = []  // 한 문장 안에서 같은 단어가 두 번 나오지 않게

        for token in Self.tokenize(pattern).tokens {
            switch token {
            case .text(let fixed):
                text += fixed
            case .slot(let category):
                let choices = words[category, default: []].filter { !usedWords.contains($0) }
                let word = choices.randomElement(using: &generator) ?? category
                usedWords.insert(word)
                text += word
            case .choice(let options):
                text += options.indices.contains(level.rawValue) ? options[level.rawValue] : options.first ?? ""
            }
        }
        return KoreanParticle.resolve(in: text)
    }

    /// 패턴의 오타를 찾는다. 문제가 없으면 빈 배열.
    func problems(in pattern: String) -> [String] {
        let (tokens, syntaxProblems) = Self.tokenize(pattern)
        var problems = syntaxProblems
        var hasChoice = false

        for token in tokens {
            switch token {
            case .text:
                break
            case .slot(let category):
                if words[category, default: []].isEmpty {
                    problems.append("없는 카테고리 {\(category)}")
                }
            case .choice(let options):
                hasChoice = true
                if options.count != SpeechLevel.allCases.count {
                    problems.append("[ ] 안에는 해요체|합쇼체|반말 세 가지를 적어야 해요: [\(options.joined(separator: "|"))]")
                }
                if options.contains(where: { $0.contains("{") }) {
                    problems.append("[ ] 안에는 {카테고리}를 쓸 수 없어요")
                }
            }
        }
        if !hasChoice {
            problems.append("말투를 고르는 [해요체|합쇼체|반말]이 없어요")
        }
        if let marker = KoreanParticle.markers.first(where: { pattern.contains(" " + $0) }) {
            problems.append("조사 표시 \(marker)는 앞 단어에 붙여 써야 해요")
        }
        return problems
    }

    /// 7개 단모음 개수가 얼마나 들쭉날쭉한지 (변동계수 = 표준편차 ÷ 평균). 0이면 완전히 고르다.
    static func vowelImbalance(_ counts: [KoreanVowel: Int]) -> Double {
        let values = KoreanVowel.allCases.map { Double(counts[$0, default: 0]) }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return .infinity }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot() / mean
    }

    // MARK: - 패턴 읽기

    private enum Token {
        case text(String)
        case slot(String)        // {카테고리}
        case choice([String])    // [해요체|합쇼체|반말]
    }

    /// 패턴을 글자 조각, {카테고리}, [말투 선택]으로 나눈다. 괄호 짝이 안 맞으면 문제로 알린다.
    private static func tokenize(_ pattern: String) -> (tokens: [Token], problems: [String]) {
        var tokens: [Token] = []
        var problems: [String] = []
        var rest = Substring(pattern)

        while let first = rest.first {
            switch first {
            case "{", "[":
                let closing: Character = first == "{" ? "}" : "]"
                guard let end = rest.firstIndex(of: closing) else {
                    problems.append("'\(first)'의 짝 '\(closing)'가 없어요")
                    tokens.append(.text(String(rest)))
                    return (tokens, problems)
                }
                let inside = String(rest[rest.index(after: rest.startIndex)..<end])
                if first == "{" {
                    tokens.append(.slot(inside))
                } else {
                    tokens.append(.choice(inside.split(separator: "|", omittingEmptySubsequences: false).map(String.init)))
                }
                rest = rest[rest.index(after: end)...]
            case "}", "]":
                problems.append("짝이 없는 '\(first)'")
                rest = rest.dropFirst()
            default:
                let end = rest.firstIndex(where: { "{[}]".contains($0) }) ?? rest.endIndex
                tokens.append(.text(String(rest[..<end])))
                rest = rest[end...]
            }
        }
        return (tokens, problems)
    }
}

/// 앞 글자의 받침을 보고 조사를 고른다. 예: 친구을(를) → 친구를, 지하철(으)로 → 지하철로
enum KoreanParticle {
    private static let rules: [(marker: String, afterConsonant: String, afterVowel: String)] = [
        ("을(를)", "을", "를"),
        ("이(가)", "이", "가"),
        ("은(는)", "은", "는"),
        ("과(와)", "과", "와"),
        ("(으)로", "으로", "로"),
    ]

    static var markers: [String] { rules.map(\.marker) }

    static func resolve(in text: String) -> String {
        var result = text
        for rule in rules {
            while let range = result.range(of: rule.marker) {
                let finalConsonant = result[..<range.lowerBound].last.flatMap { finalConsonantIndex(of: $0) }
                let particle: String
                switch finalConsonant {
                case nil, 0?:
                    particle = rule.afterVowel        // 받침 없음 (한글이 아니어도 이쪽)
                case 8? where rule.marker == "(으)로":
                    particle = rule.afterVowel        // ㄹ 받침 뒤의 (으)로는 "로": 지하철로
                default:
                    particle = rule.afterConsonant
                }
                result.replaceSubrange(range, with: particle)
            }
        }
        return result
    }

    /// 한글 음절의 받침 번호. 0 = 받침 없음, 8 = ㄹ. 한글 음절이 아니면 nil.
    /// 한글 음절의 코드 = 0xAC00 + (초성 × 21 + 중성) × 28 + 종성
    static func finalConsonantIndex(of character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        return (scalar.value - 0xAC00) % 28
    }
}
