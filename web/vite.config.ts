/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  // 상대 경로로 만든다: GitHub Pages의 하위 주소(/VOICE-TRAINING/)와 APK 안 어디에 두어도 열리게.
  base: './',
  // 대본(PracticeScripts.json)은 iOS 폴더의 파일을 그대로 읽는다 (web/ 밖이라 개발 서버에 열어 둔다).
  server: {
    fs: { allow: ['..'] },
  },
  test: {
    include: ['test/**/*.test.ts'],
  },
})
