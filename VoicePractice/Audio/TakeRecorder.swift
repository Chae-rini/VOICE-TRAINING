import Accelerate
import AVFoundation
import os

/// 녹음 한 번 동안 들어온 소리를 메모리에 모은다. 파일로 저장하지 않는다.
/// 오디오 스레드가 쓰고 메인 스레드가 읽으므로 잠금으로 보호한다.
nonisolated final class TakeRecorder: Sendable {
    /// 재생할 때 가장 큰 순간을 맞출 높이. 약 −1 dBFS (1.0이 최대).
    static let playbackPeak: Float = 0.89
    /// 재생할 때 키울 수 있는 최대 배율. 약 +24 dB. 잡음만 있는 녹음까지 크게 키우지 않기 위한 한계.
    static let maxPlaybackGain: Float = 15.85

    let sampleRate: Double  // [Hz]
    let capacity: Int       // [샘플] 이보다 많이 들어오면 뒷부분은 버린다

    private nonisolated struct State: Sendable {
        var samples: [Float] = []
        var startTime: TimeInterval?  // [s] 첫 샘플의 시각 (AudioClock 기준)
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(sampleRate: Double, maxSeconds: TimeInterval) {
        self.sampleRate = sampleRate
        let capacity = Int(sampleRate * maxSeconds)
        self.capacity = capacity
        state.withLock { $0.samples.reserveCapacity(capacity) }  // 3분이면 약 35MB를 미리 잡는다
    }

    /// 오디오 스레드에서 부른다. `time`은 이 조각 첫 샘플의 시각 [s].
    func append(_ chunk: [Float], at time: TimeInterval) {
        let capacity = capacity
        state.withLock { state in
            if state.startTime == nil {
                state.startTime = time
            }
            let room = capacity - state.samples.count
            if room > 0 {
                state.samples.append(contentsOf: chunk.prefix(room))
            }
        }
    }

    /// 첫 샘플의 시각 [s]. 아직 아무것도 녹음되지 않았으면 nil.
    var startTime: TimeInterval? {
        state.withLock { $0.startTime }
    }

    var sampleCount: Int {
        state.withLock { $0.samples.count }
    }

    /// 녹음에서 가장 큰 순간의 크기(`peak`, 0~1)를 보고 재생할 때 곱할 배율을 정한다.
    /// `.measurement` 모드는 자동 음량 조절이 없어 녹음이 작게 들어오므로, 가장 큰 순간이 `playbackPeak`가 되도록 키운다.
    /// 이미 큰 녹음은 줄이지 않고(최소 1배), 너무 작은 녹음은 `maxPlaybackGain`까지만 키운다.
    static func playbackGain(forPeak peak: Float) -> Float {
        guard peak > 0 else { return 1 }
        return min(max(playbackPeak / peak, 1), maxPlaybackGain)
    }

    /// 모은 소리로 재생용 버퍼(모노)와 곱한 배율을 돌려준다. 소리가 하나도 없으면 nil.
    func makePlaybackBuffer() -> (buffer: AVAudioPCMBuffer, gain: Float)? {
        Self.makePlaybackBuffer(samples: state.withLock { $0.samples }, sampleRate: sampleRate)
    }

    /// 들려줄 소리만 키운 재생용 버퍼를 만든다. 피치 분석은 원래 소리로 따로 한다.
    /// 목소리 판단을 흐리지 않도록 일그러뜨리는 압축 없이 전체에 같은 배율만 곱한다.
    /// 원래 소리가 필요하면(공유할 때) 버퍼를 `gain`으로 다시 나누면 된다.
    static func makePlaybackBuffer(samples original: [Float], sampleRate: Double) -> (buffer: AVAudioPCMBuffer, gain: Float)? {
        let gain = playbackGain(forPeak: vDSP.maximumMagnitude(original))
        let samples = gain == 1 ? original : vDSP.multiply(gain, original)
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                channel.update(from: base, count: source.count)
            }
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return (buffer, gain)
    }
}
