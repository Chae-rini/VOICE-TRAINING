<script lang="ts">
  import { onMount } from 'svelte'
  import HistoryScreen from './components/HistoryScreen.svelte'
  import { navigation } from './components/navigation.svelte'
  import PitchScreen from './components/PitchScreen.svelte'
  import PracticeControls from './components/PracticeControls.svelte'
  import TabBar from './components/TabBar.svelte'
  import VowelScreen from './components/VowelScreen.svelte'
  import { store } from './storage/recordStore.svelte'

  // 아래 탭: [높이] 피치 연습, [모음] 모음 지도, [기록] 날짜별 기록 (iOS `ContentView`).
  // 탭을 옮겨도 문장 카드 위치·스크롤이 그대로 남게 화면은 숨기기만 한다. 녹음·듣기 조작은 [높이]·[모음]이 같은 것을 쓴다.

  // 전에 고른 기록 폴더가 있으면 다시 연결한다 (내 기준 값은 그 폴더에 있다)
  onMount(() => {
    void store.start().then(async () => {
      // 개발 서버에서 `?seed`: [기록] 화면 확인용 가짜 기록 (기록 폴더에 연결돼 있지 않고 연습 기록이 없을 때만, 배포 빌드에는 없음)
      if (import.meta.env.DEV && new URLSearchParams(location.search).has('seed') && store.records.sessions.length === 0) {
        const { sampleRecords } = await import('./model/sampleHistory')
        const { settings } = await import('./model/settings.svelte')
        if (store.seedRecords(sampleRecords(new Date(), settings.target))) {
          store.infoMessage = '개발용 가짜 기록(40일치)을 넣었어요. 확인한 뒤 ‘모든 기록 지우기’로 지워 주세요.'
        }
      }
    })
  })
</script>

<div class="app">
  <main class="screens">
    <div class="screen" class:hidden={navigation.tab !== 'pitch'}><PitchScreen /></div>
    <div class="screen" class:hidden={navigation.tab !== 'vowel'}><VowelScreen active={navigation.tab === 'vowel'} /></div>
    <div class="screen" class:hidden={navigation.tab !== 'history'}><HistoryScreen /></div>
  </main>
  {#if navigation.tab !== 'history'}
    <PracticeControls />
  {/if}
  <TabBar />
</div>

<style>
  .app {
    height: 100dvh;
    max-width: 560px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
  }
  .screens {
    flex: 1;
    min-height: 0;
    position: relative;
  }
  .screen {
    height: 100%;
  }
  .screen.hidden {
    display: none;
  }
</style>
