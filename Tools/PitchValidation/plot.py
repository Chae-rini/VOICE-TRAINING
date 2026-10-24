"""앱의 YIN과 Praat의 프레임별 F0를 그림으로 비교한다.

사용법: python3 -I plot.py <pitch-validation 결과 폴더> <그림 저장 폴더> <recordingId> [<recordingId> ...]

- scatter_all.png : 모든 녹음의 '둘 다 유성' 프레임. 대각선에 붙을수록 일치, 2배·½배 선 위는 옥타브 오류.
- track_<id>.png  : 녹음 하나의 시간에 따른 두 곡선.
"""
import csv
import pathlib
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams["font.family"] = ["AppleGothic", "Apple SD Gothic Neo", "sans-serif"]
plt.rcParams["axes.unicode_minus"] = False

F0_RANGE = (70, 400)  # [Hz] 앱의 범위


def read_frames(path):
    times, praat, yin = [], [], []
    with open(path, encoding="utf-8") as file:
        for row in csv.DictReader(file):
            times.append(float(row["timeSeconds"]))
            praat.append(float(row["praatHz"]) if row["praatHz"] else None)
            yin.append(float(row["yinHz"]) if row["yinHz"] else None)
    return times, praat, yin


def plot_scatter(frame_files, out_path):
    xs, ys = [], []
    for path in frame_files:
        _, praat, yin = read_frames(path)
        for p, y in zip(praat, yin):
            if p is not None and y is not None and F0_RANGE[0] <= p <= F0_RANGE[1]:
                xs.append(p)
                ys.append(y)
    fig, ax = plt.subplots(figsize=(6, 6))
    ax.scatter(xs, ys, s=1, alpha=0.15, color="tab:cyan", rasterized=True)
    line = [F0_RANGE[0], F0_RANGE[1]]
    ax.plot(line, line, color="black", lw=0.8, label="y = x (일치)")
    ax.plot(line, [2 * v for v in line], color="tab:red", lw=0.8, ls="--", label="2배 / ½배 (옥타브 오류)")
    ax.plot(line, [v / 2 for v in line], color="tab:red", lw=0.8, ls="--")
    ax.set(xscale="log", yscale="log", xlim=F0_RANGE, ylim=F0_RANGE,
           xlabel="Praat F0 [Hz]", ylabel="앱 YIN F0 [Hz]",
           title=f"둘 다 유성인 프레임 {len(xs):,}개 (녹음 {len(frame_files)}개)")
    ax.legend(loc="upper left")
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def plot_track(path, out_path):
    times, praat, yin = read_frames(path)
    fig, ax = plt.subplots(figsize=(10, 3.5))
    ax.scatter([t for t, p in zip(times, praat) if p], [p for p in praat if p],
               s=4, color="gray", label="Praat")
    ax.scatter([t for t, y in zip(times, yin) if y], [y for y in yin if y],
               s=2, color="tab:cyan", label="앱 YIN")
    ax.set(ylim=F0_RANGE, xlabel="시간 [s]", ylabel="F0 [Hz]", title=path.stem)
    ax.legend(loc="upper right", markerscale=3)
    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def main():
    result_dir, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)
    frame_files = sorted((result_dir / "frames").glob("*.csv"))
    plot_scatter(frame_files, out_dir / "scatter_all.png")
    for recording_id in sys.argv[3:]:
        plot_track(result_dir / "frames" / f"{recording_id}.csv", out_dir / f"track_{recording_id}.png")


if __name__ == "__main__":
    main()
