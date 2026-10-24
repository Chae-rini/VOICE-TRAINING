import Foundation

/// 시험용 합성 모음: 성대 펄스(F0) → 포먼트 공명기(F1~F4)를 거친 소리 (Klatt식 소스-필터 합성).
/// 정답 포먼트를 알고 있는 소리로 포먼트 분석기를 확인한다.
/// 모음별 포먼트 값은 모음 사이의 상대 배치를 흉내 낸 시험용 예시일 뿐, 특정 화자 집단의 평균이 아니다.
/// 검증 도구(Tools/FormantValidation)도 이 파일을 함께 컴파일하므로 Testing을 쓰지 않는다.
enum SyntheticVowel {
    struct Shape {
        let name: String
        /// [Hz] F1, F2, F3, F4
        let formants: [Double]
    }

    static let shapes: [Shape] = [
        Shape(name: "아", formants: [800, 1300, 2600, 3500]),
        Shape(name: "어", formants: [600, 1000, 2600, 3500]),
        Shape(name: "오", formants: [450, 800, 2600, 3500]),
        Shape(name: "우", formants: [350, 900, 2500, 3500]),
        Shape(name: "으", formants: [400, 1500, 2500, 3500]),
        Shape(name: "이", formants: [300, 2300, 3000, 3700]),
        Shape(name: "에", formants: [500, 1900, 2600, 3600]),
    ]

    /// [Hz] F1~F4의 대역폭
    static let bandwidths: [Double] = [80, 100, 140, 180]

    /// `formants`를 가진 모음을 F0 `f0`로 `seconds`초 동안 낸 소리.
    static func make(formants: [Double], f0: Double, sampleRate: Double, seconds: Double) -> [Float] {
        let count = Int(sampleRate * seconds)
        // 성대를 지나는 공기 흐름: 주기마다 Rosenberg 펄스 (열리는 데 주기의 40%, 닫히는 데 16%, 나머지는 닫힘)
        // 펄스 모양이 주기에 비례하므로 음원 스펙트럼의 봉우리도 F0를 따라 움직인다 (실제 목소리와 같은 성질).
        let period = sampleRate / f0  // [샘플]
        let opening = 0.40 * period
        let closing = 0.16 * period
        var source = (0..<count).map { n -> Double in
            let t = Double(n).truncatingRemainder(dividingBy: period)
            if t <= opening {
                return 0.5 * (1 - cos(.pi * t / opening))
            } else if t <= opening + closing {
                return cos(.pi * (t - opening) / (2 * closing))
            }
            return 0
        }
        // 입술에서 퍼져 나가며 높은 쪽이 세진다(약 +6 dB/옥타브): 1차 차분
        source = zip(source, [0] + source.dropLast()).map { $0 - $1 }

        var y = source
        for (frequency, bandwidth) in zip(formants, bandwidths) {
            y = resonate(y, frequency: frequency, bandwidth: bandwidth, sampleRate: sampleRate)
        }
        let peak = y.map(abs).max() ?? 1
        return y.map { Float(0.5 * $0 / peak) }
    }

    /// 2차 공명기: y[n] = A·x[n] + B·y[n−1] + C·y[n−2]
    /// C = −e^(−2π·BW·T), B = 2e^(−π·BW·T)·cos(2π·F·T), A = 1 − B − C  (T = 1/fs)
    static func resonate(_ x: [Double], frequency: Double, bandwidth: Double, sampleRate: Double) -> [Double] {
        let t = 1 / sampleRate
        let c = -exp(-2 * .pi * bandwidth * t)
        let b = 2 * exp(-.pi * bandwidth * t) * cos(2 * .pi * frequency * t)
        let a = 1 - b - c
        var y = [Double](repeating: 0, count: x.count)
        for n in x.indices {
            y[n] = a * x[n] + b * (n >= 1 ? y[n - 1] : 0) + c * (n >= 2 ? y[n - 2] : 0)
        }
        return y
    }

    /// 소리의 0.2초 지점부터 hop마다 frameLength 길이로 자른 조각들 (첫 부분의 울림 시작은 건너뛴다)
    static func frames(_ signal: [Float], sampleRate: Double, frameLength: Int = 2048, hop: Int = 1024, count: Int = 9) -> [[Float]] {
        let start = Int(0.2 * sampleRate)
        return (0..<count).compactMap { i in
            let from = start + i * hop
            guard from + frameLength <= signal.count else { return nil }
            return Array(signal[from..<(from + frameLength)])
        }
    }
}
