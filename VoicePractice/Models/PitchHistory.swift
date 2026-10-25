import Foundation

/// 피치 한 점: 언제(time) 몇 Hz였는지(frequency), 그때의 포먼트(F1·F2).
nonisolated struct PitchReading: Sendable {
    /// [s] AudioClock 기준 시각
    let time: TimeInterval
    /// [Hz] nil이면 무음
    let frequency: Double?
    /// F1·F2. 목소리가 잡히고 또렷한 울림을 두 개 찾았을 때만 있다.
    let formants: FormantAnalyzer.Estimate?

    init(time: TimeInterval, frequency: Double?, formants: FormantAnalyzer.Estimate? = nil) {
        self.time = time
        self.frequency = frequency
        self.formants = formants
    }
}

/// 녹음 한 번 동안의 피치 기록. 그래프에는 가로축 구간(`GraphWindow`) 안의 점이 보인다.
struct PitchHistory {
    /// [s] 보관하는 길이. 녹음을 다시 들으며 처음부터 그리려면 녹음 한 번 길이만큼 남겨 둬야 한다.
    let retention: TimeInterval
    /// [s] 분석 간격 (2048샘플 창을 절반씩 밀기, 48 kHz에서 약 21 ms)
    static let readingInterval: TimeInterval = 1024.0 / 48_000

    private(set) var readings: [PitchReading] = []

    init(retention: TimeInterval = 11) {
        self.retention = retention
    }

    mutating func append(contentsOf newReadings: [PitchReading]) {
        readings.append(contentsOf: newReadings)
        guard let newest = readings.last?.time else { return }
        let cutoff = newest - retention
        if let firstKept = readings.firstIndex(where: { $0.time >= cutoff }) {
            readings.removeFirst(firstKept)
        }
    }

    mutating func removeAll() {
        readings.removeAll()
    }

    /// 꺾은선으로 이을 유성 구간들. 이웃한 유성 점 사이가 `maxGap` [s]보다 벌어지면 선을 끊는다.
    /// 분석 간격이 약 21ms라서, 0.05초로 두면 점이 하나 빠진 곳은 잇고 그보다 긴 무음은 비워 둔다.
    /// `range`를 주면 그 시간 안의 점만 쓴다 (다시 듣기 중에는 아직 재생되지 않은 뒷부분을 그리지 않는다).
    func voicedSegments(maxGap: TimeInterval = 0.05, within range: ClosedRange<TimeInterval>? = nil) -> [[PitchReading]] {
        var segments: [[PitchReading]] = []
        var current: [PitchReading] = []
        for reading in readings where reading.frequency != nil {
            if let range, !range.contains(reading.time) { continue }
            if let last = current.last, reading.time - last.time > maxGap {
                segments.append(current)
                current = []
            }
            current.append(reading)
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    /// 그래프에 그릴 유성 구간들 (`window` 안, `end` 시각까지). `width`: 그래프 가로 폭의 픽셀 수.
    /// 가로축이 길어 한 픽셀 열에 점이 두 개 넘게 몰리면, 열마다 한 점(그 열의 목소리 높이 평균)으로 묶는다.
    /// 3분이면 점이 8천 개가 넘는데 화면은 1천 픽셀 남짓이라, 다 그리면 느리기만 하고 보이는 모양은 같다.
    /// 묶은 칸 사이에 목소리 없는 칸이 끼면 선을 끊는다.
    func displaySegments(in window: GraphWindow, until end: TimeInterval, width: Double) -> [[PitchReading]] {
        // 흐르는 그래프의 왼쪽 끝에서 선이 끊겨 보이지 않게 조금 앞부터 그린다 (그래프 밖은 잘라 낸다).
        let range = (window.start - 0.5)...max(window.start - 0.5, min(end, window.end))
        let bucket = window.duration / max(width, 1)  // [s] 한 픽셀 열의 길이
        guard bucket > Self.readingInterval * 2 else {
            return voicedSegments(within: range)
        }

        var segments: [[PitchReading]] = []
        var current: [PitchReading] = []
        var bucketIndex: Int?
        var sum = 0.0
        var count = 0
        func closeBucket() {
            guard let bucketIndex, count > 0 else { return }
            let point = PitchReading(time: window.start + (Double(bucketIndex) + 0.5) * bucket,
                                     frequency: sum / Double(count))
            if let last = current.last, point.time - last.time > bucket * 1.5 {
                segments.append(current)
                current = []
            }
            current.append(point)
        }
        for reading in readings(in: range) {
            guard let frequency = reading.frequency else { continue }
            let index = Int(((reading.time - window.start) / bucket).rounded(.down))
            if index != bucketIndex {
                closeBucket()
                bucketIndex = index
                sum = 0
                count = 0
            }
            sum += frequency
            count += 1
        }
        closeBucket()
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    /// `range` 시간 안의 점들. 기록은 시간 순서라 이진 탐색으로 시작 위치를 찾는다 (화면이 초당 30번 부른다).
    func readings(in range: ClosedRange<TimeInterval>) -> ArraySlice<PitchReading> {
        var low = 0
        var high = readings.count
        while low < high {
            let middle = (low + high) / 2
            if readings[middle].time < range.lowerBound {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var end = low
        while end < readings.count, readings[end].time <= range.upperBound {
            end += 1
        }
        return readings[low..<end]
    }

    /// `time` 직전의 피치 [Hz]. `tolerance` [s]보다 오래된 값이거나 무음이면 nil.
    func frequency(at time: TimeInterval, tolerance: TimeInterval = 0.3) -> Double? {
        guard let reading = readings.last(where: { $0.time <= time && $0.frequency != nil }),
              time - reading.time <= tolerance else {
            return nil
        }
        return reading.frequency
    }
}

/// 그래프가 지금 무엇을 보여 주는지: 가로축 구간과 "지금"(녹음 중) 또는 재생 위치.
enum GraphClock: Equatable {
    /// 녹음 중: 실제 지금. 가로축은 최근 `duration`초 (오른쪽 끝이 지금). `start`: 녹음을 시작한 시각, `round`: 몇 번째 녹음인지
    case live(start: TimeInterval, duration: TimeInterval, round: Int?)
    /// 멈춘 화면: 마지막 녹음의 구간을 그대로 보여 준다. `at`: 녹음이 끝난 시각. 녹음이 없으면 둘 다 nil
    case frozen(GraphWindow?, at: TimeInterval?)
    /// 녹음을 다시 듣는 중: 녹음 구간 전체를 보이고, 재생 위치가 녹음 첫 소리(`takeStart`)부터 재생된 만큼 움직인다
    case replay(GraphWindow, takeStart: TimeInterval, playbackStart: TimeInterval)

    /// 시간에 따라 움직이는지 (움직일 때만 화면을 계속 다시 그린다)
    var isMoving: Bool {
        switch self {
        case .live, .replay: true
        case .frozen: false
        }
    }

    /// "지금"의 시각 [s, AudioClock 기준]: 녹음 중이면 지금, 다시 듣는 중이면 재생 위치, 멈췄으면 녹음이 끝난 시각
    func endTime(now: TimeInterval) -> TimeInterval {
        switch self {
        case .live: now
        case .frozen(_, let time): time ?? now
        case .replay(_, let takeStart, let playbackStart): takeStart + (now - playbackStart)
        }
    }

    /// 가로축 구간. 아직 녹음이 없으면 nil
    func window(now: TimeInterval) -> GraphWindow? {
        switch self {
        case .live(let start, let duration, let round):
            GraphWindow.live(recordingStart: start, now: now, duration: duration, round: round)
        case .frozen(let window, _): window
        case .replay(let window, _, _): window
        }
    }
}
