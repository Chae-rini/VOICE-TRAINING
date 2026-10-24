import Accelerate
import AVFoundation

/// 녹음 파일(음성 메모 등)을 읽어 피치를 미리 계산하고, 공유용 WAV·기록용 m4a 파일을 만든다.
/// 모두 기기 안에서만 처리한다. 화면이 멈추지 않도록 백그라운드에서 부를 수 있게 메인 액터에 묶지 않는다.
nonisolated enum AudioFileAnalyzer {
    /// [s] 불러오는 최대 길이. 더 긴 파일은 앞부분만 쓴다 (5분이면 약 58MB).
    static let maxSeconds: TimeInterval = 300

    nonisolated struct Analysis: Sendable {
        /// 모노로 합친 원래 소리
        let samples: [Float]
        let sampleRate: Double         // [Hz]
        /// 피치 기록. 시각은 파일 처음부터 [s]
        let readings: [PitchReading]
        /// 길어서 앞부분만 불러왔는지
        let wasTruncated: Bool

        var duration: TimeInterval { Double(samples.count) / sampleRate }
    }

    enum AnalysisError: Error {
        case emptyFile
    }

    /// 파일을 읽어(최대 `maxSeconds`) 모노로 바꾸고, 연습할 때와 같은 방식으로 피치를 계산한다.
    static func analyze(url: URL, maxSeconds: TimeInterval = maxSeconds) throws -> Analysis {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let maxFrames = AVAudioFramePosition(maxSeconds * format.sampleRate)
        let frameCount = AVAudioFrameCount(min(file.length, maxFrames))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AnalysisError.emptyFile
        }
        try file.read(into: buffer, frameCount: frameCount)

        let samples = mono(buffer)
        guard !samples.isEmpty else { throw AnalysisError.emptyFile }
        return Analysis(
            samples: samples,
            sampleRate: format.sampleRate,
            readings: pitchReadings(samples, sampleRate: format.sampleRate),
            wasTruncated: file.length > maxFrames
        )
    }

    /// 여러 채널이면 평균해서 하나로 합친다.
    static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channels = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var mono = Array(UnsafeBufferPointer(start: channels[0], count: frames))
        guard channelCount > 1 else { return mono }
        for channel in 1..<channelCount {
            mono = vDSP.add(mono, UnsafeBufferPointer(start: channels[channel], count: frames))
        }
        return vDSP.multiply(1 / Float(channelCount), mono)
    }

    /// 연습할 때와 같은 방식(2048샘플 창을 절반씩 겹쳐 밀기)으로 처음부터 끝까지 피치와 포먼트를 계산한다.
    static func pitchReadings(_ samples: [Float], sampleRate: Double) -> [PitchReading] {
        let detector = PitchDetector(sampleRate: sampleRate)
        let formantAnalyzer = FormantAnalyzer(sampleRate: sampleRate)
        let frameLength = detector.frameLength
        let hopLength = frameLength / 2
        var readings: [PitchReading] = []
        var start = 0
        while start + frameLength <= samples.count {
            let frame = Array(samples[start..<(start + frameLength)])
            let estimate = detector.detect(frame)
            let centerTime = Double(start + frameLength / 2) / sampleRate  // 창 한가운데 시각 [s]
            // 목소리가 잡힌 조각에서만 포먼트를 잰다 (무음·잡음의 가짜 울림을 피함).
            let formants = estimate == nil ? nil : formantAnalyzer.estimate(frame)
            readings.append(PitchReading(time: centerTime, frequency: estimate?.frequency, formants: formants))
            start += hopLength
        }
        return readings
    }

    /// 공유용으로 16비트 WAV 파일을 만든다 (거의 모든 앱이 열 수 있는 형식).
    static func writeWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
        try write(samples: samples, sampleRate: sampleRate, to: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
    }

    /// 기록 보관용으로 AAC(m4a) 파일을 만든다. 모노 64 kbps라 1분에 약 0.5MB.
    /// 압축은 높은 소리부터 덜어내므로, 피치·포먼트를 재는 5.5 kHz 아래는 거의 그대로 남는다.
    static func writeM4A(samples: [Float], sampleRate: Double, to url: URL) throws {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        // 낮은 샘플레이트에서는 64 kbps를 받지 않는 경우가 있어 인코더가 정하게 둔다.
        if sampleRate >= 44_100 {
            settings[AVEncoderBitRateKey] = 64_000
        }
        try write(samples: samples, sampleRate: sampleRate, to: url, settings: settings)
    }

    private static func write(samples: [Float], sampleRate: Double, to url: URL, settings: [String: Any]) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw AnalysisError.emptyFile
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: source.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)

        // 파일은 이 함수가 끝나며 닫힌다.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
