<script lang="ts">
  import { analyzeSamples } from './dsp/analysis'

  // W0~W1 자리표시 화면: 분석 코드가 브라우저에서 돌아가는지만 보여 준다. [높이] 화면은 W3에서 만든다.
  const sampleRate = 48_000 // [Hz]
  const f0 = 180 // [Hz] 배음 8개를 섞은 합성음 (k번째 배음 진폭 ∝ 1/k)
  const samples = Float32Array.from({ length: sampleRate }, (_, j) => {
    let sum = 0
    for (let k = 1; k <= 8; k++) sum += (0.3 / k) * Math.sin(2 * Math.PI * f0 * k * (j / sampleRate))
    return sum
  })
  const voiced = analyzeSamples(samples, sampleRate).flatMap((r) => (r.frequency === null ? [] : [r.frequency]))
  const measured = voiced.length > 0 ? voiced.reduce((a, b) => a + b, 0) / voiced.length : null
</script>

<main>
  <h1>울림</h1>
  <p class="note">웹 버전을 만드는 중이에요. 지금은 분석 코드만 들어 있어요.</p>
  <p data-testid="self-check">
    분석 확인: {f0} Hz 합성음 →
    {measured === null ? '목소리를 찾지 못함' : `${measured.toFixed(1)} Hz (점 ${voiced.length}개)`}
  </p>
</main>

<style>
  main {
    max-width: 480px;
    margin: 0 auto;
    padding: 24px 16px;
  }
  .note {
    color: var(--secondary);
  }
</style>
