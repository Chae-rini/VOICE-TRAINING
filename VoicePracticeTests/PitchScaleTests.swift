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

    @Test("[높이] 그래프 세로축: 목표 범위 ±50 Hz, 분석 범위(70~400 Hz) 안으로, 목표가 없으면 전체")
    func graphRange() {
        #expect(PitchScale.graphRange(around: 135...175) == 85...225)
        #expect(PitchScale.graphRange(around: 90...120) == 70...170)    // 아래 끝에 붙인다
        #expect(PitchScale.graphRange(around: 330...390) == 280...400)  // 위 끝에 붙인다
        #expect(PitchScale.graphRange(around: nil) == 70...400)
        // 좁아진 세로축에도 눈금이 3개 이상
        #expect(PitchScale.ticks(in: PitchScale.graphRange(around: 135...175)).count >= 3)
        #expect(PitchScale.ticks(in: PitchScale.graphRange(around: 210...230)).count >= 3)
        // [높이] 그래프는 눈금을 5개 이상 (좁아진 세로축에서 읽기 쉽게)
        #expect(PitchScale.ticks(in: 85...225, minimumCount: 5) == [90, 100, 125, 150, 175, 200])
        #expect(PitchScale.ticks(in: 70...400, minimumCount: 5) == [70, 100, 150, 200, 300, 400])
        // 같은 목표 범위를 반음으로 보면 전체 축(70~400 Hz)보다 크게 보인다
        let full = PitchScale.semitones(from: 70, to: 400)
        let zoomed = PitchScale.semitones(from: 85, to: 225)
        #expect(full / zoomed > 1.7)
    }

    @Test("눈금: 전체 범위는 70·100·150·200·300·400, 좁은 범위는 더 촘촘한 묶음에서 3개 이상")
    func ticks() {
        #expect(PitchScale.ticks(in: axis) == [70, 100, 150, 200, 300, 400])
        #expect(PitchScale.ticks(in: 125...245) == [125, 150, 175, 200])
        #expect(PitchScale.ticks(in: 175...240).count >= 3)
        #expect(PitchScale.ticks(in: 175...240).allSatisfy { (175...240).contains($0) })
    }

    @Test("공명 밝기(F2) 눈금: 넓으면 800·1000·1500·2000·2500, 좁으면 더 촘촘한 묶음에서 3개 이상")
    func formantTicks() {
        #expect(PitchScale.formantTicks(in: 600...3000) == [600, 800, 1000, 1500, 2000, 2500, 3000])
        #expect(PitchScale.formantTicks(in: 800...2600) == [800, 1000, 1500, 2000, 2500])
        // 공명 밝기 그래프의 가장 좁은 축(반음 6개, 약 1.41배)
        #expect(PitchScale.formantTicks(in: 1100...2200) == [1200, 1400, 1600, 1800, 2000, 2200])
        #expect(PitchScale.formantTicks(in: 1250...1767) == [1300, 1400, 1500, 1600, 1700])
        #expect(PitchScale.formantTicks(in: 1500...1610) == [1500, 1550, 1600])
    }

    @Test("세로축 밖: 두 점이 모두 같은 쪽 밖일 때만 (끝에 붙인 점선으로 그릴 구간)")
    func beyondAxis() {
        let range = 70.0...170.0
        #expect(PitchScale.isBeyond(180, 190, range: range))       // 둘 다 위
        #expect(PitchScale.isBeyond(60, 65, range: range))         // 둘 다 아래
        #expect(!PitchScale.isBeyond(160, 180, range: range))      // 하나는 안 → 끝까지 실선
        #expect(!PitchScale.isBeyond(60, 180, range: range))       // 위아래로 가로지름
        #expect(!PitchScale.isBeyond(170, 170, range: range))      // 끝 위는 안
    }
}
