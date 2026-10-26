import Accelerate
import AVFoundation
import SwiftData

/// 녹음 한 번의 묶음: 들려줄 소리, 시작 시각과 길이, 그 구간의 피치·포먼트 기록, 기록에 남겼으면 그 기록의 ID.
/// 요약 카드·기록에 남기기·AI 공유·다시 듣기는 모두 이 묶음 안의 것만 쓴다.
/// (예전에는 화면 그래프용 기록을 그대로 써서, 소리보다 2초 긴 구간이나 그 뒤의 재기 결과가 수치에 섞였다.)
struct RecordedTake {
    let id = UUID()
    /// 들려줄 수 있게 키운 소리
    let buffer: AVAudioPCMBuffer
    /// [s] 첫 샘플의 시각. 피치 기록과 같은 시계를 쓴다 (불러온 파일은 0)
    let startTime: TimeInterval
    /// 재생용으로 곱한 배율. 원래 소리 = buffer ÷ playbackGain
    let playbackGain: Float
    /// 녹음을 마친(또는 파일을 불러온) 때
    let recordedAt: Date
    /// 화면에 보일 이름 ("방금 녹음" 또는 불러온 파일 이름)
    let title: String
    /// 기록에 남길 때의 제목. 불러온 파일은 파일 이름, 방금 녹음한 것은 빈 글자
    let archiveTitle: String
    /// 연습 중에 녹음했으면 그 연습의 언어. 불러온 파일은 nil (남길 때 고른 언어를 쓴다)
    let language: PracticeLanguage?
    /// 이 소리 구간(첫 샘플~마지막 샘플)의 피치·포먼트 점
    let readings: [PitchReading]
    /// [s] 그래프 가로축 길이. 연습 녹음은 녹음할 때의 ‘들려줄 길이’, 불러온 파일은 0 (파일 길이만큼)
    let graphDuration: TimeInterval
    /// [s] 연습 녹음을 시작한 시각 (‘녹음 시작’ 선과 가로축 시간의 기준). 불러온 파일은 nil
    let recordingStart: TimeInterval?
    /// 반복 루프에서 몇 번째 녹음인지 (1부터). 불러온 파일은 nil
    let round: Int?
    /// 기록에 남겼으면 그 기록(`SavedRecording`)의 ID
    var savedRecordID: PersistentIdentifier?

    /// `readings`에서 이 소리 구간에 든 점만 잘라 담는다. 점의 시각은 분석 창의 한가운데다.
    init(buffer: AVAudioPCMBuffer, startTime: TimeInterval, playbackGain: Float, recordedAt: Date = .now,
         title: String, archiveTitle: String, language: PracticeLanguage?, readings: [PitchReading],
         graphDuration: TimeInterval = 0, recordingStart: TimeInterval? = nil, round: Int? = nil) {
        self.buffer = buffer
        self.startTime = startTime
        self.playbackGain = playbackGain
        self.recordedAt = recordedAt
        self.title = title
        self.archiveTitle = archiveTitle
        self.language = language
        self.graphDuration = graphDuration
        self.recordingStart = recordingStart
        self.round = round
        let endTime = startTime + Double(buffer.frameLength) / buffer.format.sampleRate
        self.readings = readings.filter { $0.time >= startTime && $0.time <= endTime }
    }

    /// [s] 소리 길이
    var duration: TimeInterval {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }

    /// [s] 마지막 샘플 바로 뒤의 시각
    var endTime: TimeInterval {
        startTime + duration
    }

    /// 이 녹음의 요약. 목소리가 한 번도 안 잡혔으면 nil.
    func summary(target: ClosedRange<Double>?) -> PitchSummary? {
        PitchSummary(readings: readings, duration: duration, target: target)
    }

    /// 이 녹음의 구절별 문장 끝 분석 (요약과 같은 목표 범위로). 기준값 파일을 읽지 못했으면 nil.
    func phraseEndings(target: ClosedRange<Double>?) -> PhraseEndingAnalysis? {
        PhraseEndingRules.standard.map { PhraseEndingAnalysis(readings: readings, target: target, rules: $0) }
    }

    /// [Hz] 녹음 전체의 F2 중앙값 (공명 밝기). 포먼트가 충분히 잡히지 않았으면 nil.
    var f2Median: Double? {
        ResonanceMeter.median(readings)
    }

    /// 다시 들을 때 그래프에 그릴 기록
    var history: PitchHistory {
        var history = PitchHistory(retention: duration + 2)
        history.append(contentsOf: readings)
        return history
    }

    /// 재생용으로 키우기 전의 원래 소리
    var originalSamples: [Float]? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let boosted = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        return playbackGain == 1 ? boosted : vDSP.divide(boosted, playbackGain)
    }
}
