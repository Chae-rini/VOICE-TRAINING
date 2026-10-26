<script lang="ts">
  import { PitchSummary } from '../dsp/pitchSummary'
  import { PRACTICE_LANGUAGES, recordingDisplayTitle, type PracticeLanguage, type RecordingRecord } from '../model/records'
  import { session } from '../practice/session.svelte'
  import { saveFile as saveToDevice } from '../practice/sharing'
  import { store } from '../storage/recordStore.svelte'
  import { formatFullDateTime } from '../text/dates'
  import { navigation } from './navigation.svelte'

  /**
   * 남긴 녹음 하나 (iOS `RecordingDetailView`): 요약 수치, 메모·언어 고치기, 다시 듣기([높이]에서 곡선과 함께), 파일로 저장, 지우기.
   */
  let { record, onBack }: { record: RecordingRecord; onBack: () => void } = $props()

  let memo = $state('')
  let hasSound: boolean | null = $state(null)
  let message: string | null = $state(null)
  /** 앱에서 ‘파일로 저장’한 위치 (웹은 내려받기라 없다) */
  let savedPath: string | null = $state(null)

  // 다른 녹음을 열면 메모 칸과 소리 파일 확인을 새로 한다
  $effect(() => {
    const fileName = record.fileName
    memo = record.memo
    hasSound = null
    message = null
    savedPath = null
    void store.readRecording(fileName).then((blob) => {
      if (record.fileName === fileName) hasSound = blob !== null
    })
  })

  const pitch = $derived(record.pitch)

  async function saveMemo() {
    const trimmed = memo.trim()
    if (trimmed === record.memo) return
    const result = await store.updateRecord('recordings', record.id, { memo: trimmed })
    message = result === 'failed' ? (store.errorMessage ?? '메모를 고치지 못했어요.') : null
  }

  async function setLanguage(language: PracticeLanguage) {
    const result = await store.updateRecord('recordings', record.id, { language })
    message = result === 'failed' ? (store.errorMessage ?? '언어를 고치지 못했어요.') : null
  }

  async function play() {
    // 재생은 누른 그때 소리를 준비해야 한다 (아이폰 사파리)
    session.prepareAudio()
    const sound = await store.readRecording(record.fileName)
    if (sound === null) {
      hasSound = false
      return
    }
    navigation.tab = 'pitch'
    await session.openSavedRecording(record, sound)
  }

  async function saveFile() {
    const sound = await store.readRecording(record.fileName)
    if (sound === null) {
      hasSound = false
      return
    }
    try {
      savedPath = await saveToDevice(new File([sound], record.fileName, { type: 'audio/wav' }))
    } catch {
      message = '파일로 저장하지 못했어요. 저장 공간을 확인해 주세요.'
    }
  }

  async function remove() {
    if (!confirm('이 녹음을 지울까요?\n소리 파일과 요약, 메모가 기록에서 지워져요. 되돌릴 수 없어요.')) return
    const result = await store.removeRecord('recordings', record.id)
    if (result === 'failed') message = store.errorMessage ?? '지우지 못했어요.'
    else onBack()
  }
</script>

<div class="detail">
  <button class="plain back" onclick={onBack}>‹ 기록</button>
  <h2>{recordingDisplayTitle(record)}</h2>

  <section class="card">
    <div class="line"><span>남긴 때</span><span>{formatFullDateTime(new Date(record.recordedAt))}</span></div>
    <div class="line"><span>길이</span><span>{PitchSummary.durationLabel(pitch.duration)}</span></div>
    <label class="line">
      <span>말한 언어</span>
      <select
        value={record.language}
        onchange={(event) => setLanguage((event.currentTarget as HTMLSelectElement).value as PracticeLanguage)}
      >
        {#each PRACTICE_LANGUAGES as language (language.id)}
          <option value={language.id}>{language.label}</option>
        {/each}
      </select>
    </label>
  </section>

  <section class="card">
    <h3>높이</h3>
    <div class="line"><span>중앙</span><span>{Math.round(pitch.median)} Hz</span></div>
    <div class="line"><span>범위 (아래 10%~위 10%)</span><span>{Math.round(pitch.p10)}–{Math.round(pitch.p90)} Hz</span></div>
    {#if pitch.target !== null}
      <div class="line"><span>그때 목표 범위</span><span>{Math.trunc(pitch.target.lower)}–{Math.trunc(pitch.target.upper)} Hz</span></div>
      <div class="line">
        <span>목표 범위 안</span>
        <span>{pitch.inTargetFraction === null ? '–' : `${Math.round(pitch.inTargetFraction * 100)}%`}</span>
      </div>
    {:else}
      <div class="line"><span>그때 목표 범위</span><span>정하지 않음</span></div>
    {/if}
  </section>

  <section class="card">
    <h3>메모</h3>
    <textarea bind:value={memo} onchange={saveMemo} rows="3" maxlength="500" placeholder="어떤 연습이었는지 적어 두세요" aria-label="메모"
    ></textarea>
  </section>

  <section class="card">
    <button class="fill" onclick={play} disabled={session.isRunning || hasSound === false}>▶ 다시 듣고 곡선 보기</button>
    <p class="note">
      {hasSound === false
        ? '소리 파일을 찾을 수 없어요. 숫자 기록만 남아 있어요.'
        : session.isRunning
          ? '연습을 멈춘 뒤에 들을 수 있어요.'
          : '[높이]로 가서 재생하며 그때의 곡선을 다시 그려요.'}
    </p>
    <button onclick={saveFile} disabled={hasSound === false}>⤓ 파일로 저장</button>
    <p class="note">
      {store.isApp
        ? `WAV 파일을 휴대폰의 ‘${store.appExportFolder}’에 저장해요.`
        : 'WAV 파일을 이 기기에 내려받아요 (브라우저에 따라 저장할 곳을 물어요).'}
    </p>
    {#if savedPath !== null}
      <p class="saved" role="status">‘{savedPath}’에 저장했어요.</p>
    {/if}
  </section>

  {#if message !== null}
    <p class="warning" role="alert">{message}</p>
  {/if}

  <button class="danger" onclick={remove}>이 녹음 지우기</button>
</div>

<style>
  .detail {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .back {
    align-self: flex-start;
  }
  h2 {
    margin: 0;
    font-size: 1.15rem;
    word-break: keep-all;
  }
  h3 {
    margin: 0;
    font-size: 0.9rem;
  }
  .card {
    background: var(--card);
    border-radius: 16px;
    padding: 14px 16px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 0.9rem;
  }
  .line {
    display: flex;
    justify-content: space-between;
    gap: 12px;
  }
  .line > span:first-child {
    color: var(--secondary);
  }
  .line > span:last-child {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  select {
    font: inherit;
    color: var(--target);
    background: var(--fill);
    border: none;
    border-radius: 8px;
    padding: 4px 8px;
  }
  textarea {
    font: inherit;
    color: var(--text);
    background: var(--background);
    border: 1px solid var(--divider);
    border-radius: 10px;
    padding: 8px 10px;
    resize: vertical;
  }
  .fill {
    background: var(--target);
    color: #ffffff;
    padding: 12px 16px;
  }
  .note {
    margin: -4px 0 0;
    color: var(--secondary);
    font-size: 0.75rem;
  }
  .warning {
    margin: 0;
    color: var(--warning);
    font-size: 0.85rem;
  }
  .saved {
    margin: 0;
    color: var(--record);
    font-size: 0.8rem;
  }
  .danger {
    background: color-mix(in srgb, #ff3b30 14%, transparent);
    color: #ff3b30;
    padding: 12px 16px;
  }
</style>
