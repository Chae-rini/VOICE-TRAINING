"""구절별 문장 끝 분석의 테스트 입력 파일(VoicePracticeTests/PhraseEndingCases.json)을 만든다.

사용법 (저장소 맨 위에서): python3 -I Tools/PhraseEndingCases/make_cases.py

iOS 테스트(VoicePracticeTests/PhraseEndingAnalysisTests.swift)와 웹 테스트(web/test/phraseEnding.test.ts)가
이 파일 하나를 읽어 같은 기대값과 비교한다. 두 쪽이 모두 통과하면 iOS와 웹이 같은 결과를 낸다는 뜻이다.

기대값은 앱 코드를 돌려 얻은 것이 아니라, 아래에 경우마다 손으로 셈한 값이다 (주석에 셈을 적었다).
점 간격은 앱과 같은 48 kHz의 1024샘플(약 21.3 ms)이다. 그러면 끝 300 ms 안에는 마지막 점을 포함해 15개가 들어간다
(14 × 21.3 ms = 298.7 ms ≤ 300 ms < 15 × 21.3 ms).
"""
import json
import math
import pathlib

DT = 1024 / 48_000  # [s] 점 간격
OUT = pathlib.Path(__file__).resolve().parents[2] / "VoicePracticeTests" / "PhraseEndingCases.json"


def t(k):
    """k번째 점의 시각 [s]. 더해 가지 않고 곱해서 반올림 오차가 쌓이지 않게 한다."""
    return k * 1024 / 48_000


def semitones_down(hz, n):
    """[Hz] hz에서 반음 n개 아래"""
    return hz * 2 ** (-n / 12)


def drop(phrase_median, end_median):
    """[반음] 12·log₂(구절 중앙값 ÷ 끝 중앙값)"""
    return 12 * math.log2(phrase_median / end_median)


def frames(*parts):
    """(개수, Hz 또는 None) 묶음들을 시간 순서의 [시각, Hz] 점으로 편다."""
    points = []
    for count, hz in parts:
        for _ in range(count):
            points.append([t(len(points)), hz])
    return points


def phrase(start, end, voiced, ending, phrase_median, end_median, end_floor, below, end_type, fry):
    return {
        "startTime": t(start),
        "endTime": t(end),
        "voicedFrameCount": voiced,
        "endFrameCount": ending,
        "phraseMedian": phrase_median,
        "endMedian": end_median,
        "endFloor": end_floor,
        "endDropSemitones": drop(phrase_median, end_median),
        "endBelowTarget": below,
        "endType": end_type,
        "possibleFry": fry,
    }


def summary(phrases, below_count, out_at_end, end_share):
    drops = [p["endDropSemitones"] for p in phrases]
    falling = sum(p["endType"] in ("falling", "dropping") for p in phrases)
    return {
        "phraseCount": len(phrases),
        "meanEndDropSemitones": sum(drops) / len(drops) if drops else None,
        "fallingOrDroppingCount": falling,
        "fallingOrDroppingFraction": falling / len(phrases) if phrases else None,
        "endBelowTargetCount": below_count,
        "possibleFryCount": sum(p["possibleFry"] for p in phrases),
        "outOfTargetAtEndFraction": out_at_end,
        "endFrameShare": end_share,
    }


LEAD = (10, None)  # 앞뒤 무음 10점
LOW4 = semitones_down(200, 4)  # 약 158.74 Hz
HIGH3 = semitones_down(200, -3)  # 약 237.84 Hz

cases = []

# 1. 평평한 구절: 200 Hz 60점 (k = 10~69). 끝 15점도 200 Hz → 하강 0, stable. 목표 밖 점이 없으니 비율은 null.
p = [phrase(10, 69, 60, 15, 200, 200, 200, False, "stable", False)]
cases.append({
    "name": "평평한 구절",
    "target": [180, 220],
    "readings": frames(LEAD, (60, 200), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 0, None, 15 / 60)},
})

# 2. 4반음 하강: 200 Hz 45점 (k = 10~54) + 끝 15점(k = 55~69)이 4반음 아래.
# 구절 중앙값 = 60점 중 30·31번째 = 200, 끝 중앙값·바닥 = 158.74 → 하강 4반음, falling. 바닥 < 목표 하한 180.
# 목표 밖 15점이 모두 끝에 있다(1.0). 끝은 전체의 15/60.
p2 = [phrase(10, 69, 60, 15, 200, LOW4, LOW4, True, "falling", False)]
case2_readings = frames(LEAD, (45, 200), (15, LOW4), LEAD)
cases.append({
    "name": "4반음 하강",
    "target": [180, 220],
    "readings": case2_readings,
    "expected": {"phrases": p2, "summary": summary(p2, 1, 1.0, 15 / 60)},
})

# 3. 질문형 상승: 200 Hz 45점 + 끝 15점이 3반음 위 → 하강 −3반음, rise. 끝이 목표 상한 220 위라 목표 밖 15점이 모두 끝에.
p = [phrase(10, 69, 60, 15, 200, HIGH3, HIGH3, False, "rise", False)]
cases.append({
    "name": "질문형 상승",
    "target": [180, 220],
    "readings": frames(LEAD, (45, 200), (15, HIGH3), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 0, 1.0, 15 / 60)},
})

# 4. 끝에 90 Hz 6점 연속 (긁히는 소리 가능성) + 비교용으로 무성음 한 점이 끼어 2점씩만 이어진 구절.
# fry 기준 = max(100, 180 × 0.55 = 99) = 100 Hz. 48 kHz 간격에서 최소 연속은 ⌈50 ms / 21.3 ms⌉ = 3점.
# 구절 1: 180 Hz 50점(k = 10~59) + 90 Hz 6점(k = 60~65). 56점 중앙값(28·29번째) = 180.
#   끝 15점(k = 51~65) = 180 × 9 + 90 × 6 → 중앙값(8번째) 180, 바닥(10%: 위치 1.4) 90 → 하강 0, stable. 90 Hz 6점 연속 → fry.
# 무음 15점(k = 66~80, 320 ms) → 구절이 나뉜다.
# 구절 2: 180 Hz 50점(k = 81~130) + 90, 90, (무음), 90, 90 (k = 131, 132, 134, 135). 54점 중앙값 = 180.
#   끝(k = 121~135)의 유성 14점 = 180 × 10 + 90 × 4 → 중앙값(위치 6.5) 180, 바닥(위치 1.3) 90.
#   90 Hz는 4점이지만 무음 때문에 2점씩만 이어져 fry가 아니다.
# 목표 150~210 밖은 90 Hz 10점, 모두 끝에 있다. 끝은 전체 110점 중 15 + 14 = 29점.
p = [
    phrase(10, 65, 56, 15, 180, 180, 90, True, "stable", True),
    phrase(81, 135, 54, 14, 180, 180, 90, True, "stable", False),
]
cases.append({
    "name": "끝에 90 Hz 6점 연속 (긁히는 소리 가능성), 끊긴 2점씩은 아님",
    "target": [150, 210],
    "readings": frames(LEAD, (50, 180), (6, 90), (15, None), (50, 180), (2, 90), (1, None), (2, 90), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 2, 1.0, 29 / 110)},
})

# 5. 무성음 250 ms로 나뉜 두 구절: 200 Hz 30점(k = 10~39) + 무음 12점(k = 40~51) + 170 Hz 30점(k = 52~81).
# 무음 길이 = 시각 차이 − 한 칸 = 12 × 21.3 ms = 256 ms ≥ 250 ms → 나뉜다.
# 둘째 구절은 바닥 170 < 목표 하한 180. 목표 밖 30점 중 끝 15점 → 0.5. 끝은 전체 60점 중 30점.
p = [
    phrase(10, 39, 30, 15, 200, 200, 200, False, "stable", False),
    phrase(52, 81, 30, 15, 170, 170, 170, True, "stable", False),
]
cases.append({
    "name": "무성음 250 ms로 나뉜 두 구절",
    "target": [180, 220],
    "readings": frames(LEAD, (30, 200), (12, None), (30, 170), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 1, 0.5, 30 / 60)},
})

# 5-1. 경계 확인: 무음 11점(234.7 ms < 250 ms)이면 한 구절이다. 200 Hz 30점(k = 10~39) + 무음(k = 40~50) + 170 Hz 30점(k = 51~80).
# 60점 중앙값 = (170 + 200) / 2 = 185, 끝 15점(k = 66~80)은 모두 170 → 하강 12·log₂(185/170) ≈ 1.46반음, stable.
p = [phrase(10, 80, 60, 15, 185, 170, 170, True, "stable", False)]
cases.append({
    "name": "무성음 234 ms는 나누지 않음",
    "target": [180, 220],
    "readings": frames(LEAD, (30, 200), (11, None), (30, 170), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 1, 0.5, 15 / 60)},
})

# 6. 200 ms 미만 짧은 구절: 120 Hz 9점(192 ms, k = 10~18)은 버리고, 무음 15점 뒤 200 Hz 10점(213 ms, k = 34~43)은 남긴다.
# 남은 구절은 10점이 모두 끝 300 ms 안. 목표 밖은 버린 구절의 120 Hz 9점뿐이고 끝에는 없다 → 0.0 (분모는 버린 구절까지 센다).
# 끝은 전체 19점 중 10점. 버린 구절은 fry 기준(100 Hz)보다 높고, 구절이 아니므로 fry로 세지 않는다.
p = [phrase(34, 43, 10, 10, 200, 200, 200, False, "stable", False)]
cases.append({
    "name": "200 ms 미만 짧은 구절은 버림",
    "target": [180, 220],
    "readings": frames(LEAD, (9, 120), (15, None), (10, 200), LEAD),
    "expected": {"phrases": p, "summary": summary(p, 0, 0.0, 10 / 19)},
})

# 7. 목표 범위 없음: 2번과 같은 소리. 목표에 기대는 값(끝 바닥 < 하한, 그 구절 수, 목표 밖 비율)만 null이 된다.
p = [phrase(10, 69, 60, 15, 200, LOW4, LOW4, None, "falling", False)]
cases.append({
    "name": "목표 범위 없음",
    "target": None,
    "readings": case2_readings,
    "expected": {"phrases": p, "summary": summary(p, None, None, 15 / 60)},
})

# 8. 목소리 없음: 무음 20점. 구절이 없으니 평균·비율은 null, 개수는 0.
cases.append({
    "name": "목소리 없음",
    "target": [180, 220],
    "readings": frames((20, None)),
    "expected": {"phrases": [], "summary": summary([], 0, None, None)},
})

fixture = {
    "notes": "make_cases.py가 만든 파일이라 직접 고치지 않는다. 점은 [시각 s, Hz 또는 null(무성음)]. 기대값은 손으로 셈한 값이다.",
    "frameInterval": DT,
    # 하강 폭 [반음] → 종류. 경계값은 아래 종류에 든다 (≤ −2 rise, ≤ 3 stable, ≤ 5 falling).
    "endTypeCases": [
        {"drop": -2.5, "type": "rise"},
        {"drop": -2, "type": "rise"},
        {"drop": -1.999, "type": "stable"},
        {"drop": 0, "type": "stable"},
        {"drop": 3, "type": "stable"},
        {"drop": 3.001, "type": "falling"},
        {"drop": 5, "type": "falling"},
        {"drop": 5.001, "type": "dropping"},
    ],
    # 점 간격 [s] → fry로 볼 최소 연속 점 수 (10 ms × 5 = 50 ms를 간격으로 나눠 올림)
    "fryRunCases": [
        {"frameInterval": 0.01, "frames": 5},
        {"frameInterval": 0.025, "frames": 2},
        {"frameInterval": 1024 / 48_000, "frames": 3},
        {"frameInterval": 1024 / 44_100, "frames": 3},
        {"frameInterval": 1024 / 16_000, "frames": 1},
    ],
    "cases": cases,
}

# 점 배열은 경우마다 한 줄로 쓴다 (나머지는 읽기 쉽게 들여 쓴다).
placeholders = {}
for index, case in enumerate(cases):
    key = f"@@readings{index}@@"
    placeholders[key] = json.dumps(case["readings"], separators=(",", ":"))
    case["readings"] = key
text = json.dumps(fixture, ensure_ascii=False, indent=2)
for key, value in placeholders.items():
    text = text.replace(f'"{key}"', value)
OUT.write_text(text + "\n", encoding="utf-8")
print(f"{OUT} — 경우 {len(cases)}개")
