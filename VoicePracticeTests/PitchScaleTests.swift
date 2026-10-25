import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct PitchScaleTests {
    private let axis = 70.0...400.0

    @Test("반음: 두 배는 12개, 반은 −12개, 반음 하나 옮기면 2^(1/12)배")
    func semitones() {
        #expect(abs(PitchScale.semitones(from: 110, to: 220) - 12) < 1e-9)
        #expect(abs(PitchScale.semitones(from: 220, to: 110) + 12) < 1e-9)
        #expect(abs(PitchScale.frequency(220, offsetBy: 12) - 440) < 1e-9)
        #expect(abs(PitchScale.frequency(200, offsetBy: 1) - 200 * pow(2, 1.0 / 12)) < 1e-9)
    }

    @Test("위치: 아래 끝 0, 위 끝 1, 되돌리면 같은 Hz")
    func position() {
        #expect(abs(PitchScale.position(of: 70, in: axis)) < 1e-12)
        #expect(abs(PitchScale.position(of: 400, in: axis) - 1) < 1e-12)
        for frequency in [70.0, 95, 150, 222.5, 400] {
            let back = PitchScale.frequency(atPosition: PitchScale.position(of: frequency, in: axis), in: axis)
            #expect(abs(back - frequency) < 1e-9)
        }
    }

    @Test("같은 반음 폭은 어느 높이에서든 같은 길이로 그려진다 (Hz 직선 눈금에서는 높은 쪽이 2.4배 넓었다)")
    func equalSemitonesEqualLength() {
        func length(from low: Double, semitones: Double) -> Double {
            PitchScale.position(of: PitchScale.frequency(low, offsetBy: semitones), in: axis) - PitchScale.position(of: low, in: axis)
        }
        #expect(abs(length(from: 110, semitones: 4) - length(from: 260, semitones: 4)) < 1e-12)
        #expect(abs(length(from: 80, semitones: 1) - length(from: 350, semitones: 1)) < 1e-12)

        // 예전 Hz 직선 눈금의 길이 비교: 같은 4반음인데 높은 쪽이 2.4배
        func linearLength(from low: Double, semitones: Double) -> Double {
            (PitchScale.frequency(low, offsetBy: semitones) - low) / (axis.upperBound - axis.lowerBound)
        }
        #expect(linearLength(from: 260, semitones: 4) / linearLength(from: 110, semitones: 4) > 2.3)
    }

    @Test("눈금: 전체 범위는 70·100·150·200·300·400, 좁은 범위는 더 촘촘한 묶음에서 3개 이상")
    func ticks() {
        #expect(PitchScale.ticks(in: axis) == [70, 100, 150, 200, 300, 400])
        #expect(PitchScale.ticks(in: 125...245) == [125, 150, 175, 200])
        #expect(PitchScale.ticks(in: 175...240).count >= 3)
        #expect(PitchScale.ticks(in: 175...240).allSatisfy { (175...240).contains($0) })
    }
}
