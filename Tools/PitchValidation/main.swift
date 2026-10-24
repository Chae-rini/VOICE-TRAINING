// 앱의 PitchDetector(YIN)를 실제 녹음에 돌려 Praat 프레임별 F0와 비교한다.
// 앱 빌드에는 포함되지 않는 macOS 명령줄 도구다.
//
// 빌드: xcrun swiftc -O VoicePractice/Audio/PitchDetector.swift Tools/PitchValidation/main.swift -o pitch-validation
// 실행: ./pitch-validation <audio 폴더> <frames 폴더> <결과 폴더>
//
// 음성 파일과 결과 CSV는 개인 자료이므로 프로젝트 밖(임시 폴더)에 둔다.

import AVFoundation
import Foundation

let thresholds = [0.10, 0.15, 0.20, 0.25]
let appThreshold = 0.20                         // 지금 앱의 기본값 (2026-10-24 검증 후 0.15 → 0.20)
let appRange = PitchDetector.frequencyRange     // [Hz] 70...400
let grossErrorRatio = 0.2                       // 20% 넘게 다르면 큰 오류 (GPE 관례)
let smoothingWidth = 5                          // [프레임] 이동 중앙값 실험용 폭 (10ms 간격 → 50ms)

struct PraatTrack: Decodable {
    struct Point: Decodable {
        let timeSeconds: Double
        let f0Hz: Double?
        let voiced: Bool
    }
    let recordingId: String
    let points: [Point]
}

/// 한 설정에서 모은 프레임 수와 오차.
struct Tally {
    var bothVoiced = 0
    var gross = 0
    var octave = 0
    var fineCents: [Double] = []
    var missed = 0          // Praat 유성, YIN 무성
    var falseAlarm = 0      // Praat 무성, YIN 유성
    var bothUnvoiced = 0
    var praatOutOfRange = 0 // Praat가 70~400Hz 밖으로 잡은 프레임 (비교에서 제외)

    mutating func add(praat: Double?, yin: Double?) {
        if let praat, !appRange.contains(praat) {
            praatOutOfRange += 1
            return
        }
        switch (praat, yin) {
        case let (p?, y?):
            bothVoiced += 1
            let cents = 1200 * log2(y / p)  // 100센트 = 반음
            if abs(y / p - 1) > grossErrorRatio {
                gross += 1
                if abs(abs(cents) - 1200) < 200 { octave += 1 }  // 2배 또는 ½배 근처
            } else {
                fineCents.append(cents)
            }
        case (_?, nil): missed += 1
        case (nil, _?): falseAlarm += 1
        case (nil, nil): bothUnvoiced += 1
        }
    }

    mutating func merge(_ other: Tally) {
        bothVoiced += other.bothVoiced
        gross += other.gross
        octave += other.octave
        fineCents += other.fineCents
        missed += other.missed
        falseAlarm += other.falseAlarm
        bothUnvoiced += other.bothUnvoiced
        praatOutOfRange += other.praatOutOfRange
    }

    var compared: Int { bothVoiced + missed + falseAlarm + bothUnvoiced }
    var praatVoiced: Int { bothVoiced + missed }
    var gpe: Double { ratio(gross, bothVoiced) }
    var octaveRate: Double { ratio(octave, bothVoiced) }
    var voicingAgreement: Double { ratio(bothVoiced + bothUnvoiced, compared) }
    var missRate: Double { ratio(missed, praatVoiced) }                           // 놓친 비율
    var falseAlarmRate: Double { ratio(falseAlarm, falseAlarm + bothUnvoiced) }   // 헛잡은 비율
    var fineMeanCents: Double { fineCents.isEmpty ? .nan : fineCents.reduce(0, +) / Double(fineCents.count) }
    var fineMedianAbsCents: Double { median(fineCents.map(abs)) ?? .nan }
}

func ratio(_ part: Int, _ whole: Int) -> Double {
    whole == 0 ? .nan : Double(part) / Double(whole)
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

/// 유성 프레임만 이웃 `width`개의 중앙값으로 바꾼다. 무성 구간을 채우지는 않는다.
func medianSmoothed(_ track: [Double?], width: Int) -> [Double?] {
    let half = width / 2
    return track.indices.map { i in
        guard track[i] != nil else { return nil }
        let window = track[max(0, i - half)...min(track.count - 1, i + half)].compactMap { $0 }
        return median(window)
    }
}

func loadSamples(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
          format.channelCount >= 1 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else { throw CocoaError(.fileReadCorruptFile) }
    return (Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))), format.sampleRate)
}

func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }

// MARK: - 실행

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("사용법: pitch-validation <audio 폴더> <frames 폴더> <결과 폴더>")
    exit(1)
}
let audioDirectory = URL(fileURLWithPath: arguments[1])
let framesDirectory = URL(fileURLWithPath: arguments[2])
let outputDirectory = URL(fileURLWithPath: arguments[3])
try FileManager.default.createDirectory(at: outputDirectory.appendingPathComponent("frames"), withIntermediateDirectories: true)

let trackFiles = try FileManager.default.contentsOfDirectory(at: framesDirectory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "json" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

var totals = Dictionary(uniqueKeysWithValues: thresholds.map { ($0, Tally()) })
var smoothedTotal = Tally()
var perRecordingRows = ["recordingId,durationSeconds,sampleRateHz,frames,edgeSkipped,praatMedianHz,yinMedianHz,medianDiffPercent,gpe,octaveRate,voicingAgreement,missRate,falseAlarmRate,fineMedianAbsCents,smoothedGpe,rmsRejectedPraatVoiced"]
let clock = ContinuousClock()
let started = clock.now

for trackFile in trackFiles {
    let track = try JSONDecoder().decode(PraatTrack.self, from: Data(contentsOf: trackFile))
    let (samples, sampleRate) = try loadSamples(audioDirectory.appendingPathComponent("\(track.recordingId).m4a"))

    let detectors = thresholds.map { threshold in
        let detector = PitchDetector(sampleRate: sampleRate)
        detector.threshold = threshold
        return (threshold, detector)
    }
    let frameLength = detectors[0].1.frameLength

    // RMS만 보고 무음으로 거른 프레임 수를 세려고, 임계값과 상관없이 주기성 검사를 사실상 끈 검출기도 하나 둔다.
    let permissive = PitchDetector(sampleRate: sampleRate)
    permissive.threshold = 1.0

    var praatTrack: [Double?] = []
    var yinTracks = Dictionary(uniqueKeysWithValues: thresholds.map { ($0, [Double?]()) })
    var edgeSkipped = 0
    var rmsRejectedPraatVoiced = 0

    for point in track.points {
        // Praat 프레임 시각은 분석 창의 가운데다. 같은 시각을 가운데로 둔 창을 잘라 YIN에 넣는다.
        let start = Int((point.timeSeconds * sampleRate).rounded()) - frameLength / 2
        guard start >= 0, start + frameLength <= samples.count else {
            edgeSkipped += 1
            continue
        }
        let frame = Array(samples[start..<(start + frameLength)])
        let praat = point.voiced ? point.f0Hz : nil
        praatTrack.append(praat)
        for (threshold, detector) in detectors {
            yinTracks[threshold]!.append(detector.detect(frame)?.frequency)
        }
        if let praat, appRange.contains(praat), permissive.detect(frame) == nil,
           vDSPRootMeanSquare(frame) < Double(permissive.minimumRMS) {
            rmsRejectedPraatVoiced += 1
        }
    }

    var recordingTallies: [Double: Tally] = [:]
    for threshold in thresholds {
        var tally = Tally()
        for (praat, yin) in zip(praatTrack, yinTracks[threshold]!) {
            tally.add(praat: praat, yin: yin)
        }
        recordingTallies[threshold] = tally
        totals[threshold]!.merge(tally)
    }

    let smoothed = medianSmoothed(yinTracks[appThreshold]!, width: smoothingWidth)
    var smoothedTally = Tally()
    for (praat, yin) in zip(praatTrack, smoothed) {
        smoothedTally.add(praat: praat, yin: yin)
    }
    smoothedTotal.merge(smoothedTally)

    let appTally = recordingTallies[appThreshold]!
    let praatMedian = median(praatTrack.compactMap { $0 }) ?? .nan
    let yinMedian = median(yinTracks[appThreshold]!.compactMap { $0 }) ?? .nan
    perRecordingRows.append([
        track.recordingId,
        String(format: "%.2f", Double(samples.count) / sampleRate),
        String(format: "%.0f", sampleRate),
        "\(praatTrack.count)",
        "\(edgeSkipped)",
        String(format: "%.2f", praatMedian),
        String(format: "%.2f", yinMedian),
        String(format: "%.2f", (yinMedian / praatMedian - 1) * 100),
        String(format: "%.4f", appTally.gpe),
        String(format: "%.4f", appTally.octaveRate),
        String(format: "%.4f", appTally.voicingAgreement),
        String(format: "%.4f", appTally.missRate),
        String(format: "%.4f", appTally.falseAlarmRate),
        String(format: "%.1f", appTally.fineMedianAbsCents),
        String(format: "%.4f", smoothedTally.gpe),
        "\(rmsRejectedPraatVoiced)",
    ].joined(separator: ","))

    // 그림·추가 분석용 프레임별 곡선. yinHz는 앱 기본 임계값, 뒤쪽 열은 임계값별 결과.
    let otherThresholds = thresholds.filter { $0 != appThreshold }
    var frameRows = ["timeSeconds,praatHz,yinHz,yinSmoothedHz,"
        + otherThresholds.map { String(format: "yin%03.0fHz", $0 * 100) }.joined(separator: ",")]
    let times = track.points.map(\.timeSeconds).filter { t in
        let start = Int((t * sampleRate).rounded()) - frameLength / 2
        return start >= 0 && start + frameLength <= samples.count
    }
    for (i, time) in times.enumerated() {
        let values = [praatTrack[i], yinTracks[appThreshold]![i], smoothed[i]] + otherThresholds.map { yinTracks[$0]![i] }
        let cells = values.map { $0.map { String(format: "%.2f", $0) } ?? "" }
        frameRows.append(([String(format: "%.3f", time)] + cells).joined(separator: ","))
    }
    try frameRows.joined(separator: "\n").write(
        to: outputDirectory.appendingPathComponent("frames/\(track.recordingId).csv"), atomically: true, encoding: .utf8)

    print(String(format: "%@  %.0f Hz  Praat %.1f / YIN %.1f Hz  GPE %@  유성일치 %@",
                 track.recordingId, sampleRate, praatMedian, yinMedian, percent(appTally.gpe), percent(appTally.voicingAgreement)))
}

func vDSPRootMeanSquare(_ frame: [Float]) -> Double {
    Double((frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count)).squareRoot())
}

var summary = ["# 전체 요약 (녹음 \(trackFiles.count)개, 프레임 합산)", ""]
summary.append("임계값 | 비교 프레임 | 둘 다 유성 | GPE | 옥타브 | 유성 일치 | 놓침 | 헛잡음 | 미세오차 중앙(¢) | 미세오차 평균(¢) | Praat 범위 밖")
for threshold in thresholds {
    let t = totals[threshold]!
    summary.append(String(format: "%.2f | %d | %d | %@ | %@ | %@ | %@ | %@ | %.1f | %+.1f | %d",
                          threshold, t.compared, t.bothVoiced, percent(t.gpe), percent(t.octaveRate),
                          percent(t.voicingAgreement), percent(t.missRate), percent(t.falseAlarmRate),
                          t.fineMedianAbsCents, t.fineMeanCents, t.praatOutOfRange))
}
summary.append("")
summary.append(String(format: "이동 중앙값 %d프레임 (임계값 %.2f): GPE %@, 옥타브 %@, 미세오차 중앙 %.1f¢",
                      smoothingWidth, appThreshold, percent(smoothedTotal.gpe), percent(smoothedTotal.octaveRate),
                      smoothedTotal.fineMedianAbsCents))
summary.append("실행 시간: \(clock.now - started)")

let summaryText = summary.joined(separator: "\n")
print("\n" + summaryText)
try summaryText.write(to: outputDirectory.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
try perRecordingRows.joined(separator: "\n").write(
    to: outputDirectory.appendingPathComponent("per_recording.csv"), atomically: true, encoding: .utf8)
