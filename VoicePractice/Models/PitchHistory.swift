import Foundation

/// 피치 한 점: 언제(time) 몇 Hz였는지(frequency).
nonisolated struct PitchReading: Sendable {
    /// [s] AudioClock 기준 시각
    let time: TimeInterval
    /// [Hz] nil이면 무음
    let frequency: Double?
}

/// 녹음 한 번 동안의 피치 기록. 그래프에는 그중 최근 10초만 보인다.
struct PitchHistory {
    /// [s] 그래프에 보이는 길이 (가로축)
    let visibleDuration: TimeInterval = 10
    /// [s] 보관하는 길이. 녹음을 다시 들으며 처음부터 그리려면 녹음 한 번 길이만큼 남겨 둬야 한다.
    let retention: TimeInterval

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

    /// `time` 직전의 피치 [Hz]. `tolerance` [s]보다 오래된 값이거나 무음이면 nil.
    func frequency(at time: TimeInterval, tolerance: TimeInterval = 0.3) -> Double? {
        guard let reading = readings.last(where: { $0.time <= time && $0.frequency != nil }),
              time - reading.time <= tolerance else {
            return nil
        }
        return reading.frequency
    }
}

/// 그래프의 오른쪽 끝("지금")을 어느 시각으로 볼지.
enum GraphClock: Equatable {
    /// 녹음 중: 실제 지금
    case live
    /// 멈춘 화면: 정해진 시각에 고정. nil이면 아직 기록이 없음
    case frozen(TimeInterval?)
    /// 녹음을 다시 듣는 중: 녹음 시작 시각부터 재생된 만큼 흘러간 시각
    case replay(takeStart: TimeInterval, playbackStart: TimeInterval)

    /// 시간에 따라 움직이는지 (움직일 때만 화면을 계속 다시 그린다)
    var isMoving: Bool {
        switch self {
        case .live, .replay: true
        case .frozen: false
        }
    }

    /// 그래프 오른쪽 끝의 시각 [s, AudioClock 기준]
    func endTime(now: TimeInterval) -> TimeInterval {
        switch self {
        case .live: now
        case .frozen(let time): time ?? now
        case .replay(let takeStart, let playbackStart): takeStart + (now - playbackStart)
        }
    }
}
