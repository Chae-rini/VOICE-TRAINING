import Accelerate
import AVFoundation
import os

/// 녹음하는 동안 들어온 소리 중 최근 `keepSeconds`초만 메모리에 남긴다. 파일로 저장하지 않는다.
/// 고리(ring) 모양 버퍼라서, 가득 차면 가장 오래된 소리 자리에 새 소리를 덮어쓴다.
/// 오디오 스레드가 쓰고 메인 스레드가 읽으므로 잠금으로 보호한다.
nonisolated final class TakeRecorder: Sendable {
    /// 재생할 때 가장 큰 순간을 맞출 높이. 약 −1 dBFS (1.0이 최대).
    static let playbackPeak: Float = 0.89
    /// 재생할 때 키울 수 있는 최대 배율. 약 +24 dB. 잡음만 있는 녹음까지 크게 키우지 않기 위한 한계.
    static let maxPlaybackGain: Float = 15.85

    let sampleRate: Double  // [Hz]
    let capacity: Int       // [샘플] 보관할 최대 길이. 넘치면 오래된 소리부터 버린다

    private nonisolated struct State: Sendable {
        var ring: [Float]
        var writeIndex = 0          // 다음 샘플을 쓸 자리
        var count = 0               // 지금 보관 중인 샘플 수 (최대 capacity)
        var endTime: TimeInterval?  // [s] 마지막 샘플 바로 뒤의 시각 (AudioClock 기준)
    }

    private let state: OSAllocatedUnfairLock<State>

    init(sampleRate: Double, keepSeconds: TimeInterval) {
        self.sampleRate = sampleRate
        let capacity = max(Int(sampleRate * keepSeconds), 1)
        self.capacity = capacity
        // 3분이면 약 35MB를 미리 잡는다.
        state = OSAllocatedUnfairLock(initialState: State(ring: Array(repeating: 0, count: capacity)))
    }

    /// 오디오 스레드에서 부른다. `time`은 이 조각 첫 샘플의 시각 [s].
    func append(_ chunk: [Float], at time: TimeInterval) {
        let capacity = capacity
        let endTime = time + Double(chunk.count) / sampleRate
        state.withLock { state in
            // 조각 하나가 통째로 보관 길이보다 길면 끝부분만 남긴다.
            let kept = chunk.suffix(capacity)
            // 고리의 끝까지 쓰고, 남은 것은 맨 앞으로 돌아가 이어 쓴다.
            let firstPart = min(kept.count, capacity - state.writeIndex)
            state.ring.replaceSubrange(state.writeIndex ..< state.writeIndex + firstPart, with: kept.prefix(firstPart))
            state.ring.replaceSubrange(0 ..< kept.count - firstPart, with: kept.dropFirst(firstPart))
            state.writeIndex = (state.writeIndex + kept.count) % capacity
            state.count = min(state.count + kept.count, capacity)
            state.endTime = endTime
        }
    }

    /// 보관 중인 첫 샘플의 시각 [s]. 아직 아무것도 녹음되지 않았으면 nil.
    /// 탭 조각은 빈틈없이 이어지므로 마지막 시각에서 보관 길이만큼 거슬러 올라가 구한다.
    var startTime: TimeInterval? {
        let sampleRate = sampleRate
        return state.withLock { state in
            state.endTime.map { $0 - Double(state.count) / sampleRate }
        }
    }

    var sampleCount: Int {
        state.withLock { $0.count }
    }

    /// 보관 중인 소리를 오래된 것부터 순서대로 꺼낸다.
    private func orderedSamples() -> [Float] {
        let capacity = capacity
        return state.withLock { state in
            let start = (state.writeIndex - state.count + capacity) % capacity
            if start + state.count <= capacity {
                return Array(state.ring[start ..< start + state.count])
            }
            return Array(state.ring[start...]) + state.ring[..<(start + state.count - capacity)]
        }
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
        Self.makePlaybackBuffer(samples: orderedSamples(), sampleRate: sampleRate)
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
