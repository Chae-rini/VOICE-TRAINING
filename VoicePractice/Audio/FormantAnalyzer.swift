import Accelerate

/// 포먼트 하나: 성도(목과 입안)가 울리는 주파수와 그 울림의 폭.
nonisolated struct Formant: Equatable, Sendable {
    /// [Hz] 울림의 중심 주파수
    let frequency: Double
    /// [Hz] 울림의 폭. 좁을수록 또렷한 울림이다.
    let bandwidth: Double
}

/// 복소수. LPC 다항식의 근(극점)을 다룰 때만 쓴다.
nonisolated struct Complex: Equatable, Sendable {
    var real: Double
    var imaginary: Double

    init(_ real: Double, _ imaginary: Double) {
        self.real = real
        self.imaginary = imaginary
    }

    init(radius: Double, angle: Double) {
        self.init(radius * cos(angle), radius * sin(angle))
    }

    var magnitude: Double {
        hypot(real, imaginary)
    }

    static func + (a: Complex, b: Complex) -> Complex { Complex(a.real + b.real, a.imaginary + b.imaginary) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.real - b.real, a.imaginary - b.imaginary) }

    static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.real * b.real - a.imaginary * b.imaginary, a.real * b.imaginary + a.imaginary * b.real)
    }

    static func / (a: Complex, b: Complex) -> Complex {
        let d = b.real * b.real + b.imaginary * b.imaginary
        return Complex((a.real * b.real + a.imaginary * b.imaginary) / d, (a.imaginary * b.real - a.real * b.imaginary) / d)
    }
}

/// 소리 조각 하나에서 포먼트(F1·F2)를 선형 예측(LPC)으로 잰다.
/// 오디오 스레드에서 불릴 수 있어 메인 액터에 묶지 않는다(nonisolated).
///
/// 순서: 12 kHz 안팎으로 표본 줄이기 → 고역 강조 → Hamming 창 → 자기상관
///       → Levinson–Durbin(LPC 계수) → LPC 다항식의 근(Durand–Kerner)
///       → 근의 각도 = 주파수, 반지름 = 대역폭 → 대역폭이 좁은 것 중 낮은 순서로 F1, F2.
/// 성별을 묻지 않으므로 최대 포먼트 주파수는 5500 Hz 하나로 둔다 (Praat는 성별마다 다른 값을 권한다).
nonisolated struct FormantAnalyzer {
    struct Estimate: Equatable, Sendable {
        let f1: Formant
        let f2: Formant
    }

    static let maxFormantFrequency = 5500.0  // [Hz]
    /// [Hz] 이보다 낮은 근은 포먼트가 아니라 성대 진동이나 잡음 쪽으로 본다
    static let minFormantFrequency = 90.0
    /// [Hz] 이보다 넓은 근은 또렷한 울림이 아니므로 F1·F2로 고르지 않는다
    static let maxBandwidth = 400.0
    /// 고역 강조 계수: y[n] = x[n] − 0.97·x[n−1]. 성대 음원의 내리막 기울기를 펴서 높은 포먼트도 잡히게 한다.
    static let preEmphasis = 0.97

    /// [Hz] 들어오는 소리의 표본화 주파수
    let inputSampleRate: Double
    /// 몇 개마다 하나씩 남길지 (48 kHz → 4 → 12 kHz)
    let decimationFactor: Int
    /// [Hz] 표본을 줄인 뒤의 표본화 주파수
    let analysisRate: Double
    /// LPC 차수. 기본은 표본화 주파수(kHz)와 같은 값(12 kHz → 12, 포먼트 6개까지).
    /// 흔히 쓰는 경험칙(+2)보다 2 낮다: 합성 모음 비교에서 목소리가 높을 때 F2가 더 안정적이었다 (Tools/FormantValidation).
    let order: Int
    /// [s] 분석 창 길이. nil이면 받은 조각 전체를 쓴다.
    let windowDuration: Double?
    /// 표본을 줄이기 전에 거는 저역 통과 필터 (겹침 방지)
    private let lowPass: [Float]

    /// `order`와 `windowDuration`은 검증 도구에서 여러 값을 비교할 때만 바꾼다.
    init(sampleRate: Double, order: Int? = nil, windowDuration: Double? = nil) {
        inputSampleRate = sampleRate
        let factor = max(1, Int((sampleRate / 11_000).rounded(.down)))
        decimationFactor = factor
        analysisRate = sampleRate / Double(factor)
        self.order = order ?? Int(analysisRate / 1000)
        self.windowDuration = windowDuration
        let cutoff = min(Self.maxFormantFrequency, 0.45 * analysisRate)
        lowPass = factor == 1 ? [1] : Self.lowPassFilter(cutoff: cutoff, sampleRate: sampleRate, taps: 63)
    }

    /// F1과 F2. 목소리가 없거나 또렷한 울림을 두 개 찾지 못하면 nil.
    func estimate(_ frame: [Float]) -> Estimate? {
        guard let candidates = formants(frame)?.filter({ $0.bandwidth <= Self.maxBandwidth }),
              candidates.count >= 2 else { return nil }
        return Estimate(f1: candidates[0], f2: candidates[1])
    }

    /// 포먼트 후보 전체 (주파수 오름차순, 대역폭으로 거르기 전). 검증 도구에서도 쓴다.
    func formants(_ frame: [Float]) -> [Formant]? {
        guard frame.count >= lowPass.count + decimationFactor * (order + 2) else { return nil }

        // 1. 표본 줄이기: 저역 통과 후 decimationFactor개마다 하나. 창 길이가 정해져 있으면 가운데만 쓴다.
        var decimated = vDSP.downsample(frame, decimationFactor: decimationFactor, filter: lowPass)
        if let windowDuration {
            let length = min(decimated.count, Int(windowDuration * analysisRate))
            let start = (decimated.count - length) / 2
            decimated = Array(decimated[start..<(start + length)])
        }
        guard decimated.count > order + 1 else { return nil }

        // 2. 고역 강조, 3. Hamming 창 (LPC 계산은 정밀도를 위해 Double로)
        var x = [Double](repeating: 0, count: decimated.count)
        x[0] = Double(decimated[0])
        for n in 1..<decimated.count {
            x[n] = Double(decimated[n]) - Self.preEmphasis * Double(decimated[n - 1])
        }
        x = vDSP.multiply(x, vDSP.window(ofType: Double.self, usingSequence: .hamming, count: x.count, isHalfWindow: false))

        // 4. 자기상관 r[k] = Σ x[n]·x[n+k],  k = 0…order
        let r = (0...order).map { k in vDSP.dot(x[0..<(x.count - k)], x[k...]) }
        guard r[0] > 1e-12, let a = Self.levinsonDurbin(r, order: order) else { return nil }

        // 5. A(z) = 1 + a₁z⁻¹ + … + a_p z⁻ᵖ 의 근 = zᵖ + a₁zᵖ⁻¹ + … + a_p 의 근
        // 6. 켤레 근 한 쌍이 포먼트 하나: 각도 θ → 주파수 θ·fs/2π, 반지름 r → 대역폭 −ln(r)·fs/π
        return Self.polynomialRoots([1] + a).compactMap { z -> Formant? in
            guard z.imaginary > 0 else { return nil }
            let frequency = atan2(z.imaginary, z.real) * analysisRate / (2 * .pi)
            let bandwidth = -log(z.magnitude) * analysisRate / .pi
            guard frequency > Self.minFormantFrequency, frequency < Self.maxFormantFrequency else { return nil }
            return Formant(frequency: frequency, bandwidth: bandwidth)
        }
        .sorted { $0.frequency < $1.frequency }
    }

    /// 자기상관 r[0…p]로 예측 계수 a[1…p]를 구한다 (A(z) = 1 + Σ a_k z⁻ᵏ).
    /// 토플리츠 행렬 연립방정식(정규 방정식)을 차수를 하나씩 올려 가며 O(p²)로 푼다.
    /// 반사 계수 |k| ≥ 1이면 필터가 불안정하므로 nil.
    static func levinsonDurbin(_ r: [Double], order p: Int) -> [Double]? {
        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1
        var error = r[0]
        for i in 1...p {
            var acc = r[i]
            for j in 1..<i {
                acc += a[j] * r[i - j]
            }
            let k = -acc / error  // 반사 계수
            guard abs(k) < 1 else { return nil }
            let previous = a
            for j in 1..<i {
                a[j] = previous[j] + k * previous[i - j]
            }
            a[i] = k
            error *= 1 - k * k
        }
        return Array(a[1...p])
    }

    /// 다항식 c₀zⁿ + c₁zⁿ⁻¹ + … + cₙ = 0 의 근 n개 (c₀ ≠ 0).
    /// Durand–Kerner(바이어슈트라스) 반복: 모든 근을 동시에 z_i ← z_i − P(z_i) / Π_{j≠i}(z_i − z_j) 로 고쳐 간다.
    /// LPC 차수(≈14) 정도에서는 수십 번 안에 수렴한다.
    static func polynomialRoots(_ c: [Double]) -> [Complex] {
        let n = c.count - 1
        guard n > 0, c[0] != 0 else { return [] }
        let monic = c.map { $0 / c[0] }
        // 호너법으로 P(z) 계산
        func value(_ z: Complex) -> Complex {
            monic.dropFirst().reduce(Complex(1, 0)) { $0 * z + Complex($1, 0) }
        }
        // 출발점: 반지름 0.9인 원 위에 고르게. 실수축 대칭을 피하려고 각도를 0.4 rad 비튼다.
        var roots = (0..<n).map { Complex(radius: 0.9, angle: 2 * .pi * Double($0) / Double(n) + 0.4) }
        for _ in 0..<500 {
            var largestStep = 0.0
            for i in 0..<n {
                var denominator = Complex(1, 0)
                for j in 0..<n where j != i {
                    denominator = denominator * (roots[i] - roots[j])
                }
                let step = value(roots[i]) / denominator
                roots[i] = roots[i] - step
                largestStep = max(largestStep, step.magnitude)
            }
            if largestStep < 1e-12 { break }
        }
        return roots
    }

    /// Hamming 창을 씌운 sinc 저역 통과 필터. 직류 이득이 1이 되게 맞춘다.
    static func lowPassFilter(cutoff: Double, sampleRate: Double, taps: Int) -> [Float] {
        let fc = cutoff / sampleRate  // 0 ~ 0.5
        let middle = Double(taps - 1) / 2
        let h = (0..<taps).map { n -> Double in
            let k = Double(n) - middle
            let sinc = k == 0 ? 2 * fc : sin(2 * .pi * fc * k) / (.pi * k)
            let window = 0.54 - 0.46 * cos(2 * .pi * Double(n) / Double(taps - 1))
            return sinc * window
        }
        let sum = h.reduce(0, +)
        return h.map { Float($0 / sum) }
    }
}
