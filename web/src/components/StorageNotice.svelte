<script lang="ts">
  import { settings } from '../model/settings.svelte'
  import { VowelMaps } from '../model/vowelMap'
  import { store } from '../storage/recordStore.svelte'
  import { navigation } from './navigation.svelte'

  /**
   * [높이]·[모음] 화면 위의 한 줄 안내: 기록이 파일로 남지 않고 있을 때만 보인다.
   * 버튼을 누른 그때 폴더 허락을 물을 수 있어서, 다시 연결·폴더 고르기·기록 파일 저장은 여기서 바로 한다.
   */
  const status = $derived(store.status)
  const hasValues = $derived(
    settings.target !== null || settings.baseline !== null || VowelMaps.measuredCount(settings.vowelMap) > 0,
  )
</script>

{#if status.kind === 'needsPermission'}
  <div class="notice">
    <p>기록 폴더 ‘{status.folderName}’에 다시 연결해야 목표 범위·기준·모음 지도를 불러오고 저장할 수 있어요.</p>
    <button class="small" onclick={() => store.reconnect()} disabled={store.busy}>다시 연결</button>
  </div>
{:else if store.errorMessage !== null}
  <div class="notice">
    <p>{store.errorMessage}</p>
    <button class="small" onclick={() => (navigation.tab = 'history')}>[기록]에서 보기</button>
  </div>
{:else if store.movedAppFolder !== null && !store.usedRecordFile}
  <div class="notice quiet">
    <p>앱을 다시 설치해서 이제 ‘{store.movedAppFolder}’에 저장해요. 예전 기록은 [기록]에서 기록 파일로 불러올 수 있어요.</p>
    <button class="small" onclick={() => (navigation.tab = 'history')}>[기록]으로</button>
  </div>
{:else if store.isApp && status.kind === 'none' && (store.unsaved || hasValues)}
  <div class="notice">
    <p>휴대폰의 ‘문서/울림’ 폴더를 열지 못해서, 목표 범위·기준·모음 지도가 앱을 닫으면 사라져요.</p>
    <button class="small" onclick={() => store.connectAppFolder()} disabled={store.busy}>다시 열기</button>
  </div>
{:else if status.kind === 'none' && (store.unsaved || hasValues)}
  <div class="notice">
    <p>기록 폴더를 아직 고르지 않아서, 목표 범위·기준·모음 지도는 페이지를 닫으면 사라져요.</p>
    <button class="small" onclick={() => store.chooseFolder()} disabled={store.busy}>폴더 고르기</button>
  </div>
{:else if status.kind === 'memory' && store.unsaved}
  <div class="notice">
    <p>바뀐 기록을 아직 기록 파일로 저장하지 않았어요.</p>
    <button class="small" onclick={() => store.exportFile()} disabled={store.busy}>파일로 저장</button>
  </div>
{:else if status.kind === 'memory' && !store.usedRecordFile && !hasValues}
  <div class="notice quiet">
    <p>저장해 둔 기록 파일이 있으면 [기록]에서 불러와 주세요.</p>
    <button class="small" onclick={() => (navigation.tab = 'history')}>[기록]으로</button>
  </div>
{/if}

<style>
  .notice {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: 10px;
    background: var(--card);
    color: var(--warning);
    font-size: 0.8rem;
  }
  .notice.quiet {
    color: var(--secondary);
  }
  .notice p {
    margin: 0;
    flex: 1;
  }
  .notice button {
    flex: none;
  }
</style>
