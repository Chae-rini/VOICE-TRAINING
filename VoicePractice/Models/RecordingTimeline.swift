import AVFoundation
import SwiftData

/// 녹음·재기 중에 들어오는 피치 점을 용도별로 나눠 담고, 마지막 녹음 묶음을 들고 있는다.
/// - 화면 그래프용(`display`): 최근 N초 + 여유 2초. 그리는 데만 쓴다.
/// - 재기용(`measurement`): 내 목소리·모음 재기 동안의 점. 재기 결과에만 쓴다.
/// - 마지막 녹음 묶음(`lastTake`): 소리와 같은 구간의 점. 요약 카드·기록에 남기기·AI 공유·다시 듣기에 쓴다.
/// 예전에는 한 기록을 모두가 함께 써서, 요약에 소리보다 2초 긴 구간이 섞이고 재기가 마지막 녹음의 수치를 덮어썼다.
struct RecordingTimeline {
    /// 화면 그래프용 기록
    private(set) var display = PitchHistory(retention: PracticeDuration.range.upperBound + 2)
    /// 지금 재고 있는 점 (재기 중에만 쌓인다)
    private(set) var measurement: [PitchReading] = []
    /// 마지막 녹음 (방금 녹음 또는 불러온 파일)
    private(set) var lastTake: RecordedTake?

    /// 녹음이나 재기를 새로 시작한다. `keepSeconds` [s]: 들려줄(잴) 길이.
    mutating func beginRecording(keepSeconds: TimeInterval) {
        // 그래프는 왼쪽 끝이 비지 않게 여유를 두고 그린다. 이 여유는 수치에 쓰지 않는다.
        display = PitchHistory(retention: keepSeconds + 2)
        measurement = []
    }

    /// 녹음·재기 중에 들어온 점. `isMeasuring`: 내 목소리·모음 재기 중인지.
    mutating func receive(_ readings: [PitchReading], isMeasuring: Bool) {
        display.append(contentsOf: readings)
        if isMeasuring {
            measurement.append(contentsOf: readings)
        }
    }

    /// [s] 정지로 끊은 녹음에서 목소리가 이보다 짧게 잡혔으면, 이미 있는 마지막 녹음을 덮어쓰지 않는다 (임시값, 2026-10-30).
    /// 반복 루프는 다 들은 뒤 다음 녹음을 스스로 시작해서, 그때 정지하면 빈 새 녹음이 방금 들은 녹음을 덮어썼다.
    /// 마이크 잡음이 잠깐 목소리로 잡힌 것은 거르고, 짧게라도 실제로 말한 녹음은 남기려는 값이다. 웹 `MINIMUM_STOPPED_TAKE_VOICED_SECONDS`와 같다
    static let minimumStoppedTakeVoicedSeconds: TimeInterval = 0.5

    /// 연습 녹음을 마지막 녹음으로 확정한다. 소리 구간(`startTime`부터 소리 길이만큼)의 점만 묶음에 넣는다.
    /// `graphDuration` [s]: 그래프 가로축 길이(들려줄 길이), `recordingStart` [s]: 녹음을 시작한 시각, `round`: 몇 번째 녹음인지.
    @discardableResult
    mutating func keepTake(buffer: AVAudioPCMBuffer, startTime: TimeInterval, playbackGain: Float,
                           language: PracticeLanguage?, recordedAt: Date = .now,
                           graphDuration: TimeInterval = 0, recordingStart: TimeInterval? = nil,
                           round: Int? = nil) -> RecordedTake {
        let take = makeTake(buffer: buffer, startTime: startTime, playbackGain: playbackGain, language: language,
                            recordedAt: recordedAt, graphDuration: graphDuration, recordingStart: recordingStart, round: round)
        keep(take)
        return take
    }

    /// 지금까지 들어온 점으로 녹음 묶음을 만든다 (아직 마지막 녹음으로 두지는 않는다). 인자는 `keepTake`와 같다.
    func makeTake(buffer: AVAudioPCMBuffer, startTime: TimeInterval, playbackGain: Float,
                  language: PracticeLanguage?, recordedAt: Date = .now,
                  graphDuration: TimeInterval = 0, recordingStart: TimeInterval? = nil,
                  round: Int? = nil) -> RecordedTake {
        RecordedTake(buffer: buffer, startTime: startTime, playbackGain: playbackGain, recordedAt: recordedAt,
                     title: "방금 녹음", archiveTitle: "", language: language, readings: display.readings,
                     graphDuration: graphDuration, recordingStart: recordingStart, round: round)
    }

    /// 녹음 묶음을 마지막 녹음으로 둔다. `stopped`: 정지 버튼·전화 등으로 녹음을 끊었는지.
    /// 끊은 녹음에 목소리가 거의 없고(`minimumStoppedTakeVoicedSeconds` 미만) 이미 마지막 녹음이 있으면,
    /// 새 녹음은 버리고 그래프도 마지막 녹음으로 되돌린 뒤 false를 돌려준다. ‘지금 들어보기’로 끝낸 녹음은 늘 남긴다.
    @discardableResult
    mutating func keep(_ take: RecordedTake, stopped: Bool = false) -> Bool {
        if stopped, let lastTake, take.voicedSeconds < Self.minimumStoppedTakeVoicedSeconds {
            display = lastTake.history
            return false
        }
        lastTake = take
        display = take.history
        return true
    }

    /// 재기를 마치고 잰 점을 돌려준다. 재기는 마지막 녹음을 바꾸지 않으므로, 그래프는 마지막 녹음으로 되돌린다.
    mutating func finishMeasuring() -> [PitchReading] {
        let readings = measurement
        cancelMeasuring()
        return readings
    }

    /// 재기를 중간에 멈춘다. 잰 점은 버리고 그래프는 마지막 녹음으로 되돌린다.
    mutating func cancelMeasuring() {
        measurement = []
        display = lastTake?.history ?? PitchHistory()
    }

    /// 불러온 파일 등을 마지막 녹음으로 둔다.
    mutating func load(_ take: RecordedTake) {
        lastTake = take
        display = take.history
    }

    /// 다시 듣기 전에 화면 그래프를 마지막 녹음으로 맞춘다.
    mutating func showLastTake() {
        if let lastTake {
            display = lastTake.history
        }
    }

    /// 마지막 녹음의 요약 (그 묶음의 점으로). 목소리가 한 번도 안 잡혔거나 녹음이 없으면 nil.
    func lastTakeSummary(target: ClosedRange<Double>?) -> PitchSummary? {
        lastTake?.summary(target: target)
    }

    /// 마지막 녹음의 구절별 문장 끝 분석 (그 묶음의 점으로). 녹음이 없으면 nil.
    func lastTakePhraseEndings(target: ClosedRange<Double>?) -> PhraseEndingAnalysis? {
        lastTake?.phraseEndings(target: target)
    }

    /// 기록에 남긴 뒤 그 기록의 ID를 붙인다. 남기는 동안 새 녹음으로 바뀌었으면 붙이지 않는다.
    mutating func markSaved(_ recordID: PersistentIdentifier, takeID: UUID) {
        guard lastTake?.id == takeID else { return }
        lastTake?.savedRecordID = recordID
    }
}
