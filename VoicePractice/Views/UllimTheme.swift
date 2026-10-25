import SwiftUI

/// 울림 아이콘의 네 색에 역할을 하나씩 맡긴다. 화면은 색 이름 대신 역할 이름을 쓴다.
/// 색 값은 Assets.xcassets에 있다: 밝은 모드는 아이콘 색과 같은 색상에서 밝기만 낮춘 값(흰 바탕 대비 4.5:1 이상),
/// 어두운 모드는 아이콘 색 그대로.
///
/// 분홍과 파랑은 성별과 묶여 읽히기 쉬워서, 둘을 "높은 쪽/낮은 쪽"이나 "전/후" 짝으로 쓰지 않는다 (원칙 3).
/// 분홍은 목표가 높든 낮든 늘 "지금 내 목소리"이고, 파랑은 앱 강조색과 목표 범위다.
enum UllimColor {
    /// 지금 내 목소리 (아이콘의 분홍 파형): 피치 꺾은선, 지금 높이 숫자, 모음 지도의 지금 점, 듣는 중
    static let voice = Color(.ullimPink)
    /// 목표 범위 띠와 앱 강조색 (아이콘의 가장 큰 파란 원). 버튼·슬라이더·탭도 이 색을 쓴다.
    static let target = Color.accentColor
    /// 내 기준 (보라): 기준 목소리 점선, 내 모음 지도, 내 목소리 재기, 두 녹음 비교의 A
    static let reference = Color(.ullimPurple)
    /// 기록·저장 (초록): 연습 시간 막대, 저장 완료 안내, 두 녹음 비교의 B
    static let record = Color(.ullimGreen)
    /// 목표 밖의 점, 지나간 꼬리
    static let inactive = Color.gray

    /// 목표 범위 띠처럼 넓게 칠할 때의 진하기
    static let bandOpacity = 0.18
}
