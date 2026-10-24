// 앱의 FormantAnalyzer를 정답을 아는 합성 모음에 돌려, 목소리 높이(F0)에 따라 F1·F2 오차가 어떻게 변하는지 표로 낸다.
// LPC 차수와 창 길이를 바꿔 가며 비교하고, 앱 기본값의 모음별 표와 속도도 낸다.
// 앱 빌드에는 포함되지 않는 macOS 명령줄 도구다. 개인 녹음은 쓰지 않는다.
//
// 빌드: xcrun swiftc -O VoicePractice/Audio/FormantAnalyzer.swift VoicePracticeTests/SyntheticVowel.swift Tools/FormantValidation/main.swift -o formant-validation
// 실행: ./formant-validation

import Foundation

let sampleRate = 48_000.0  // [Hz] 아이폰 마이크와 같은 값
let f0s: [Double] = [100, 150, 200, 250, 300, 350]  // [Hz]

struct Result {
    /// [모음별] F1·F2 상대 오차 (못 잡았으면 nil)
    var f1Errors: [Double?] = []
    var f2Errors: [Double?] = []
    var found: [Int] = []
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

func evaluate(_ analyzer: FormantAnalyzer, f0: Double) -> Result {
    var result = Result()
    for shape in SyntheticVowel.shapes {
        let signal = SyntheticVowel.make(formants: shape.formants, f0: f0, sampleRate: sampleRate, seconds: 0.6)
        let estimates = SyntheticVowel.frames(signal, sampleRate: sampleRate).compactMap { analyzer.estimate($0) }
        result.f1Errors.append(median(estimates.map(\.f1.frequency)).map { ($0 - shape.formants[0]) / shape.formants[0] })
        result.f2Errors.append(median(estimates.map(\.f2.frequency)).map { ($0 - shape.formants[1]) / shape.formants[1] })
        result.found.append(estimates.count)
    }
    return result
}

func worst(_ errors: [Double?]) -> Double {
    errors.map { $0.map(abs) ?? 1 }.max() ?? 1
}

func mean(_ errors: [Double?]) -> Double {
    errors.map { $0.map(abs) ?? 1 }.reduce(0, +) / Double(errors.count)
}

func percent(_ value: Double) -> String {
    String(format: "%4.1f%%", 100 * value)
}

// 1. 설정 비교: F0별 F1·F2의 평균 / 최대 오차 (7개 모음)
print("설정 비교 — 칸: F1 평균/최대 · F2 평균/최대 (7개 모음의 절대 상대 오차)")
let variants: [(String, FormantAnalyzer)] = [
    ("14차, 창 42.7ms", FormantAnalyzer(sampleRate: sampleRate, order: 14)),
    ("12차, 창 42.7ms (앱 기본)", FormantAnalyzer(sampleRate: sampleRate)),
    ("10차, 창 42.7ms", FormantAnalyzer(sampleRate: sampleRate, order: 10)),
    ("14차, 창 25ms  ", FormantAnalyzer(sampleRate: sampleRate, order: 14, windowDuration: 0.025)),
    ("12차, 창 25ms  ", FormantAnalyzer(sampleRate: sampleRate, order: 12, windowDuration: 0.025)),
]
for (name, analyzer) in variants {
    var line = "\(name) |"
    for f0 in f0s {
        let r = evaluate(analyzer, f0: f0)
        line += " \(Int(f0)): \(percent(mean(r.f1Errors)))/\(percent(worst(r.f1Errors))) · \(percent(mean(r.f2Errors)))/\(percent(worst(r.f2Errors))) |"
    }
    print(line)
}

// 2. 앱 기본값의 모음별 표
let analyzer = FormantAnalyzer(sampleRate: sampleRate)
print("\n앱 기본값: \(Int(analyzer.analysisRate)) Hz로 줄여 LPC \(analyzer.order)차, 2048샘플(42.7 ms) 조각 9개의 중앙값")
print("칸: F1 오차 / F2 오차 (잡힌 조각 수/9)")
var header = "F0(Hz) "
for shape in SyntheticVowel.shapes {
    header += "| \(shape.name)                     "
}
print(header)
for f0 in f0s {
    let r = evaluate(analyzer, f0: f0)
    var line = String(format: "%5.0f  ", f0)
    for i in SyntheticVowel.shapes.indices {
        let f1 = r.f1Errors[i].map { String(format: "%+5.1f%%", 100 * $0) } ?? "  --  "
        let f2 = r.f2Errors[i].map { String(format: "%+5.1f%%", 100 * $0) } ?? "  --  "
        line += "| \(f1) / \(f2) (\(r.found[i])/9) "
    }
    print(line)
}

// 3. 속도: 조각 하나를 분석하는 데 걸리는 시간 (이 Mac 기준, 아이폰과 다를 수 있음)
let frame = SyntheticVowel.frames(SyntheticVowel.make(formants: SyntheticVowel.shapes[0].formants, f0: 200,
                                                      sampleRate: sampleRate, seconds: 0.6), sampleRate: sampleRate)[0]
let runs = 2000
let start = Date()
var found = 0
for _ in 0..<runs where analyzer.estimate(frame) != nil {
    found += 1
}
let perFrame = Date().timeIntervalSince(start) / Double(runs) * 1e6  // [µs]
print(String(format: "\n속도: 조각 하나에 %.0f µs (조각 간격 21 ms의 %.2f%%), %d/%d 성공", perFrame, perFrame / 21_333 * 100, found, runs))
