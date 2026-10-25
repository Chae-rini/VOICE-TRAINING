/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import basicSsl from '@vitejs/plugin-basic-ssl'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig(({ mode }) => {
  // `npm run dev:lan`: 같은 와이파이의 휴대폰에서 열어 보는 임시 HTTPS 개발 서버.
  // 휴대폰 브라우저는 https 주소에서만 마이크를 켜 주므로, 개발할 때만 쓰는 임시 인증서를 만든다 (앱에는 들어가지 않는다).
  const lan = mode === 'lan'
  return {
    plugins: [svelte(), ...(lan ? [basicSsl()] : [])],
    // 상대 경로로 만든다: GitHub Pages의 하위 주소(/VOICE-TRAINING/)와 APK 안 어디에 두어도 열리게.
    base: './',
    server: {
      host: lan ? true : 'localhost',
      fs: {
        // 개발 서버가 내줄 수 있는 파일을 web/ 폴더와 대본 파일 하나로 좁힌다.
        // 저장소 맨 위에는 개인 녹음 자료(Validation/)와 서명 설정이 있어서, 와이파이로 열어 둘 때 새지 않게 한다.
        allow: ['.', '../VoicePractice/Models/PracticeScripts.json'],
      },
    },
    test: {
      include: ['test/**/*.test.ts'],
    },
  }
})
