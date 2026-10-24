import Accelerate

/// 한 프레임에서 찾은 피치.
nonisolated struct PitchEstimate: Sendable, Equatable {
    /// 기본주파수 F0 [Hz]
    let frequency: Double
    /// 0~1. 1에 가까울수록 주기성이 뚜렷하다 (= 1 − d′(τ)).
    let confidence: Double
}

/// 외부 라이브러리 없이 Accelerate(vDSP)로 구현한 YIN 피치 검출기.
///
/// 참고 논문: A. de Cheveigné & H. Kawahara,
/// "YIN, a fundamental frequency estimator for speech and music", JASA 111(4), 2002.
/// 논문의 1~4단계를 구현했다. 5~6단계(주변 프레임과 비교해 다듬기)는 생략.
///
/// 오디오 스레드에서 쓰므로 메인 액터에 묶지 않는다(nonisolated).
/// 내부 작업 버퍼를 재사용하므로 한 인스턴스를 여러 스레드에서 동시에 쓰면 안 된다.
nonisolated final class PitchDetector {
    static let frequencyRange: ClosedRange<Double> = 70...400  // [Hz] 이 밖의 결과는 버린다

    let sampleRate: Double  // [Hz]
    let frameLength: Int    // 한 번에 분석하는 샘플 수

    /// d′(τ)가 이 값 아래로 내려가야 "주기적인 소리"로 인정한다. 논문 권장은 0.10~0.15.
    /// 실제 녹음 32개로 Praat와 비교했을 때 0.20이 큰 오류를 늘리지 않으면서
    /// 소리 시작·끝을 덜 놓쳤다 (Validation/YIN_vs_Praat.md).
    var threshold = 0.20
    /// RMS 음량이 이보다 작으면 무음. 약 −54 dBFS. 실제 기기에서 조정이 필요할 수 있다.
    var minimumRMS: Float = 0.002

    private let maxLag: Int        // 가장 낮은 주파수(70Hz)의 한 주기 [샘플]
    private let windowLength: Int  // 차이를 합산하는 구간 W [샘플]

    private var samples: [Double]
    private var correlation: [Double]  // r(τ)
    private var difference: [Double]   // d(τ)
    private var normalized: [Double]   // d′(τ)

    init(sampleRate: Double, frameLength: Int? = nil) {
        let maxLag = Int((sampleRate / Self.frequencyRange.lowerBound).rounded(.up))
        // 70Hz 한 주기를 비교하려면 W ≥ maxLag 여야 한다. 48kHz에서는 2048이면 충분하다.
        let length = frameLength ?? max(2048, 2 * maxLag + 2)
        // τ = maxLag + 1까지 계산해 둬야 maxLag에서도 4단계 보간을 할 수 있다.
        let windowLength = length - (maxLag + 1)
        precondition(windowLength >= maxLag, "frameLength가 너무 짧습니다")

        self.sampleRate = sampleRate
        self.frameLength = length
        self.maxLag = maxLag
        self.windowLength = windowLength
        samples = Array(repeating: 0, count: length)
        correlation = Array(repeating: 0, count: maxLag + 2)
        difference = Array(repeating: 0, count: maxLag + 2)
        normalized = Array(repeating: 0, count: maxLag + 2)
    }

    /// `frame`(길이 = frameLength)의 피치를 찾는다. 무음이거나 믿을 수 없으면 nil.
    func detect(_ frame: [Float]) -> PitchEstimate? {
        precondition(frame.count == frameLength)

        // 0단계 — 음량 확인: 너무 조용하면 계산할 필요 없이 무음.
        guard vDSP.rootMeanSquare(frame) >= minimumRMS else { return nil }

        // 1단계에서 큰 수끼리 빼는 계산이 있어 Double로 바꿔 정밀도를 확보한다.
        vDSP.convertElements(of: frame, to: &samples)

        computeDifference()
        computeCumulativeMeanNormalizedDifference()
        // 주기성이 약하면(숨소리·잡음) 무음으로 처리한다.
        guard let lag = findFirstDip() else { return nil }

        let frequency = sampleRate / refineLag(lag)
        guard Self.frequencyRange.contains(frequency) else { return nil }
        return PitchEstimate(frequency: frequency, confidence: min(1, max(0, 1 - normalized[lag])))
    }

    /// 1단계 — 차이 함수 (difference function)
    ///
    ///     d(τ) = Σ_{j=0}^{W−1} (x_j − x_{j+τ})²
    ///
    /// 신호를 τ 샘플만큼 밀어서 원래 신호와 얼마나 다른지 잰다.
    /// τ가 한 주기와 같으면 두 신호가 겹쳐서 d(τ) ≈ 0 이 된다.
    /// 빼기라서 마이크의 직류 성분(DC offset)은 저절로 상쇄된다.
    ///
    /// 그대로 계산하면 τ마다 W번씩 곱해야 해서 느리다. 제곱을 전개하면
    ///
    ///     d(τ) = e₀ + e_τ − 2·r(τ)
    ///     e₀   = Σ x_j²          앞 구간의 에너지 (τ와 무관)
    ///     e_τ  = Σ x_{j+τ}²      τ만큼 민 구간의 에너지
    ///     r(τ) = Σ x_j·x_{j+τ}   자기상관 (autocorrelation)
    ///
    /// 이 되고, 무거운 r(τ)는 vDSP 상관 연산 한 번으로 모든 τ를 구한다.
    private func computeDifference() {
        // vectorized: r(τ), τ = 0...maxLag+1 을 한 번에 계산
        vDSP.correlate(samples, withKernel: samples[0..<windowLength], result: &correlation)

        let e0 = correlation[0]
        var shiftedEnergy = e0
        for lag in 0...(maxLag + 1) {
            if lag > 0 {
                // 구간이 한 칸 밀리면 맨 앞 샘플이 빠지고 맨 뒤 샘플이 새로 들어온다.
                let leaving = samples[lag - 1]
                let entering = samples[lag - 1 + windowLength]
                shiftedEnergy += entering * entering - leaving * leaving
            }
            // 반올림 오차로 아주 작은 음수가 나올 수 있어 0에서 자른다.
            difference[lag] = max(0, e0 + shiftedEnergy - 2 * correlation[lag])
        }
    }

    /// 2단계 — 누적 평균 정규화 차이 (cumulative mean normalized difference)
    ///
    ///     d′(0) = 1,   d′(τ) = d(τ) / [ (1/τ) · Σ_{j=1}^{τ} d(j) ]
    ///
    /// d(τ)를 "지금까지의 평균"으로 나눠, 소리 크기와 상관없이 1 근처에서 시작하는 값으로 만든다.
    /// d(τ)만 쓰면 τ = 0에서 항상 0이라 최솟값을 고를 수 없는데, 이 정규화가 그 문제를 없앤다.
    private func computeCumulativeMeanNormalizedDifference() {
        normalized[0] = 1
        var runningSum = 0.0
        for lag in 1...(maxLag + 1) {
            runningSum += difference[lag]
            normalized[lag] = runningSum > 0 ? difference[lag] * Double(lag) / runningSum : 1
        }
    }

    /// 3단계 — 절대 임계값 (absolute threshold)
    ///
    /// d′(τ)가 threshold 아래로 처음 내려가는 τ를 찾고, 그 골짜기의 바닥까지 따라간다.
    /// "가장 작은 τ"를 고르는 이유: 주기의 2배·3배인 τ에서도 d′가 작아지는데,
    /// 그쪽을 고르면 실제보다 한 옥타브 낮게 읽는다(옥타브 오류).
    /// τ = 2부터 찾기 때문에 400Hz보다 높은 소리는 반 주파수로 잘못 읽지 않고 범위 밖으로 버려진다.
    private func findFirstDip() -> Int? {
        var lag = 2
        while lag <= maxLag {
            if normalized[lag] < threshold {
                while lag + 1 <= maxLag, normalized[lag + 1] < normalized[lag] {
                    lag += 1
                }
                return lag
            }
            lag += 1
        }
        return nil
    }

    /// 4단계 — 포물선 보간 (parabolic interpolation)
    ///
    /// τ는 정수(샘플 단위)라서 48kHz·200Hz 근처에서는 한 칸이 약 0.8Hz다.
    /// 이웃한 세 점 d(τ−1), d(τ), d(τ+1)에 포물선을 맞춰 골짜기의 진짜 바닥(소수 τ)을 찾는다.
    /// 논문대로 정규화 전의 d(τ)에 맞춘다 (d′는 정규화 때문에 바닥 위치가 살짝 치우친다).
    private func refineLag(_ lag: Int) -> Double {
        let left = difference[lag - 1]
        let center = difference[lag]
        let right = difference[lag + 1]
        let curvature = left - 2 * center + right
        guard curvature > 0 else { return Double(lag) }
        // 포물선 꼭짓점: τ + (y₋ − y₊) / (2·(y₋ − 2y₀ + y₊))
        let offset = (left - right) / (2 * curvature)
        return Double(lag) + min(1, max(-1, offset))
    }
}
