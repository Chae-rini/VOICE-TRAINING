// 웹 버전(web/)의 분석 코드가 iOS 앱과 같은 숫자를 내는지 확인할 정답표를 만든다.
// 앱의 PitchDetector·FormantAnalyzer에 합성 신호를 넣어 결과를 JSON으로 쓴다. 웹 테스트(web/test/golden.test.ts)가
// 같은 식으로 같은 신호를 만들어 TypeScript 분석 결과와 비교한다. 개인 녹음은 쓰지 않는다.
// 앱 빌드에는 포함되지 않는 macOS 명령줄 도구다.
//
// 빌드: xcrun swiftc -O VoicePractice/Audio/PitchDetector.swift VoicePractice/Audio/FormantAnalyzer.swift VoicePracticeTests/SyntheticVowel.swift Tools/WebGolden/main.swift -o web-golden
// 실행: ./web-golden web/test/golden/swift-golden.json

import Accelerate
import Foundation

// MARK: - 합성 신호 (web/test/signals.ts와 같은 식)

func sine(_ frequency: Double, sampleRate: Double, count: Int, amplitude: Double = 0.5) -> [Float] {
    (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

/// 배음 8개, k번째 배음의 진폭 0.3/k
func harmonic(_ f0: Double, sampleRate: Double, count: Int) -> [Float] {
    (0..<count).map { j in
        let t = Double(j) / sampleRate
        return Float((1...8).reduce(0.0) { sum, k in sum + 0.3 / Double(k) * sin(2 * .pi * f0 * Double(k) * t) })
    }
}

/// 높이가 `from`에서 `to`로 고르게 오르는 소리 (선형 처프)
func glide(from: Double, to: Double, seconds: Double, sampleRate: Double, amplitude: Double) -> [Float] {
    (0..<Int(sampleRate * seconds)).map { n in
        let t = Double(n) / sampleRate
        let phase = 2 * .pi * (from * t + (to - from) * t * t / (2 * seconds))
        return Float(amplitude * sin(phase))
    }
}

/// SplitMix64. 웹 쪽도 같은 수열을 만든다.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ≤ u < 1 (위 53비트)
    mutating func uniform() -> Double {
        Double(next() >> 11) * 0x1p-53
    }
}

/// −amplitude ~ +amplitude 균등 분포 잡음
func noise(count: Int, amplitude: Double, seed: UInt64) -> [Float] {
    var generator = SplitMix64(state: seed)
    return (0..<count).map { _ in Float((generator.uniform() * 2 - 1) * amplitude) }
}

func dBFS(_ frame: [Float]) -> Double {
    let rms = Double(vDSP.rootMeanSquare(frame))
    return rms > 0 ? max(20 * log10(rms), -100) : -100
}

// MARK: - 정답표 형식

struct PitchResult: Codable {
    let input: Double
    let sampleRate: Double
    let frequency: Double?
    let confidence: Double?
}

struct Reading: Codable {
    let time: Double
    let frequency: Double?
    let level: Double
    let f1: Double?
    let f2: Double?
}

struct GlideCase: Codable {
    let sampleRate: Double
    let from: Double
    let to: Double
    let seconds: Double
    let amplitude: Double
    let readings: [Reading]
}

struct VowelFrame: Codable {
    let frequency: Double?
    let f1: Double?
    let f1Bandwidth: Double?
    let f2: Double?
    let f2Bandwidth: Double?
    /// 대역폭으로 거르기 전의 후보 [주파수, 대역폭]
    let candidates: [[Double]]
}

struct VowelCase: Codable {
    let name: String
    let formants: [Double]
    let f0: Double
    let sampleRate: Double
    let frames: [VowelFrame]
}

struct Intermediates: Codable {
    /// 48 kHz 저역 통과 필터 63탭 (Float)
    let lowPass48k: [Float]
    /// vDSP Hamming 창 (count 개)
    let hammingCount: Int
    let hamming: [Double]
    /// 합성 모음 ‘아’(F0 150 Hz, 48 kHz) 첫 조각을 표본 줄인 결과
    let decimated: [Float]
    /// 같은 조각의 LPC 계수 a₁…a₁₂
    let lpc: [Double]
    /// (z−0.5)(z+0.25)(z²−z+0.5)의 근 [실수부, 허수부]
    let roots: [[Double]]
}

struct Golden: Codable {
    let note: String
    let sines: [PitchResult]
    let harmonic: PitchResult
    let noisyTone: PitchResult
    let noiseOnly: PitchResult
    let glide: GlideCase
    let vowels: [VowelCase]
    let intermediates: Intermediates
}

// MARK: - 만들기

func pitch(_ detector: PitchDetector, _ frame: [Float], input: Double) -> PitchResult {
    let estimate = detector.detect(frame)
    return PitchResult(input: input, sampleRate: detector.sampleRate, frequency: estimate?.frequency,
                       confidence: estimate?.confidence)
}

var sines: [PitchResult] = []
for sampleRate in [44_100.0, 48_000.0] {
    let detector = PitchDetector(sampleRate: sampleRate)
    for frequency in [50.0, 75, 120, 200, 350, 399, 500, 800] {
        sines.append(pitch(detector, sine(frequency, sampleRate: sampleRate, count: detector.frameLength), input: frequency))
    }
}

let detector48 = PitchDetector(sampleRate: 48_000)
let harmonicResult = pitch(detector48, harmonic(180, sampleRate: 48_000, count: detector48.frameLength), input: 180)
let tone = sine(200, sampleRate: 48_000, count: detector48.frameLength)
let noisy = zip(tone, noise(count: detector48.frameLength, amplitude: 0.05, seed: 42)).map { $0 + $1 }
let noisyResult = pitch(detector48, noisy, input: 200)
let noiseOnlyResult = pitch(detector48, noise(count: detector48.frameLength, amplitude: 0.3, seed: 7), input: 0)

// 높이가 오르는 소리: 앱이 녹음 파일을 분석하는 방식(2048샘플 창, 절반씩 밀기)으로 처음부터 끝까지
let glideSamples = glide(from: 120, to: 260, seconds: 1.5, sampleRate: 48_000, amplitude: 0.4)
let formantAnalyzer48 = FormantAnalyzer(sampleRate: 48_000)
var glideReadings: [Reading] = []
var start = 0
while start + detector48.frameLength <= glideSamples.count {
    let frame = Array(glideSamples[start..<(start + detector48.frameLength)])
    let estimate = detector48.detect(frame)
    let formants = estimate == nil ? nil : formantAnalyzer48.estimate(frame)
    glideReadings.append(Reading(time: Double(start + detector48.frameLength / 2) / 48_000, frequency: estimate?.frequency,
                                 level: dBFS(frame), f1: formants?.f1.frequency, f2: formants?.f2.frequency))
    start += detector48.frameLength / 2
}

// 합성 모음: 7개 모음 × F0 4개 (48 kHz) + ‘아’ 150 Hz (44.1 kHz)
var vowels: [VowelCase] = []
let vowelCases: [(SyntheticVowel.Shape, Double, Double)] =
    SyntheticVowel.shapes.flatMap { shape in [100.0, 150, 200, 250].map { (shape, $0, 48_000.0) } }
    + [(SyntheticVowel.shapes[0], 150, 44_100)]
for (shape, f0, sampleRate) in vowelCases {
    let detector = PitchDetector(sampleRate: sampleRate)
    let analyzer = FormantAnalyzer(sampleRate: sampleRate)
    let signal = SyntheticVowel.make(formants: shape.formants, f0: f0, sampleRate: sampleRate, seconds: 0.6)
    let frames = SyntheticVowel.frames(signal, sampleRate: sampleRate).map { frame in
        let estimate = analyzer.estimate(frame)
        return VowelFrame(frequency: detector.detect(frame)?.frequency,
                          f1: estimate?.f1.frequency, f1Bandwidth: estimate?.f1.bandwidth,
                          f2: estimate?.f2.frequency, f2Bandwidth: estimate?.f2.bandwidth,
                          candidates: (analyzer.formants(frame) ?? []).map { [$0.frequency, $0.bandwidth] })
    }
    vowels.append(VowelCase(name: shape.name, formants: shape.formants, f0: f0, sampleRate: sampleRate, frames: frames))
}

// 중간값: 어긋나면 어느 단계에서 갈라졌는지 찾을 수 있게
let lowPass = FormantAnalyzer.lowPassFilter(cutoff: 5400, sampleRate: 48_000, taps: 63)  // 48 kHz: min(5500, 0.45·12000)
let hammingCount = 497
let hamming = vDSP.window(ofType: Double.self, usingSequence: .hamming, count: hammingCount, isHalfWindow: false)
let firstFrame = SyntheticVowel.frames(SyntheticVowel.make(formants: SyntheticVowel.shapes[0].formants, f0: 150,
                                                           sampleRate: 48_000, seconds: 0.6), sampleRate: 48_000)[0]
let decimated = vDSP.downsample(firstFrame, decimationFactor: 4, filter: lowPass)
var x = [Double](repeating: 0, count: decimated.count)
x[0] = Double(decimated[0])
for n in 1..<decimated.count {
    x[n] = Double(decimated[n]) - FormantAnalyzer.preEmphasis * Double(decimated[n - 1])
}
x = vDSP.multiply(x, vDSP.window(ofType: Double.self, usingSequence: .hamming, count: x.count, isHalfWindow: false))
let r = (0...12).map { k in vDSP.dot(x[0..<(x.count - k)], x[k...]) }
let lpc = FormantAnalyzer.levinsonDurbin(r, order: 12) ?? []
let roots = FormantAnalyzer.polynomialRoots([1, -1.25, 0.625, 0, -0.0625]).map { [$0.real, $0.imaginary] }

let golden = Golden(
    note: "Tools/WebGolden이 iOS 앱의 PitchDetector·FormantAnalyzer로 만든 정답표. 손으로 고치지 말고 도구로 다시 만든다.",
    sines: sines, harmonic: harmonicResult, noisyTone: noisyResult, noiseOnly: noiseOnlyResult,
    glide: GlideCase(sampleRate: 48_000, from: 120, to: 260, seconds: 1.5, amplitude: 0.4, readings: glideReadings),
    vowels: vowels,
    intermediates: Intermediates(lowPass48k: lowPass, hammingCount: hammingCount, hamming: hamming,
                                 decimated: decimated, lpc: lpc, roots: roots)
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "swift-golden.json"
try encoder.encode(golden).write(to: URL(fileURLWithPath: output))
print("정답표를 썼다: \(output) (합성 모음 \(vowels.count)개, 오르는 소리 점 \(glideReadings.count)개)")
