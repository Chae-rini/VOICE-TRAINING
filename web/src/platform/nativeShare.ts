import { Directory, Filesystem } from '@capacitor/filesystem'
import { Share } from '@capacitor/share'
import { APP_RECORD_FOLDER_NAME, APP_RECORD_ROOT, writeNativeBytes } from '../storage/nativeFolder'

/**
 * 안드로이드 앱에서 파일로 저장·공유하기. 앱의 웹뷰는 내려받기와 공유 창(Web Share)이 안 되어서(A1 확인) 앱 기능을 쓴다.
 * 보낼 곳·저장할 곳은 여전히 사용자가 고르고, 앱이 스스로 어디로 보내지는 않는다 (원칙 2).
 */

/** ‘문서/울림’ 안에서 ‘파일로 저장’·‘기록 파일로 저장’이 쓰는 폴더 */
export const EXPORT_DIRECTORY = '내보낸 파일'

/** 파일을 휴대폰의 ‘문서/울림/내보낸 파일’에 저장하고, 화면에 보일 위치를 돌려준다. 같은 이름이 있으면 바꿔 쓴다 */
export async function saveToAppDocuments(file: File): Promise<string> {
  const path = `${APP_RECORD_ROOT}/${EXPORT_DIRECTORY}/${file.name}`
  await writeNativeBytes(Filesystem, path, Directory.Documents, new Uint8Array(await file.arrayBuffer()))
  return `${APP_RECORD_FOLDER_NAME}/${EXPORT_DIRECTORY}/${file.name}`
}

export type AppShareResult = 'shared' | 'cancelled' | 'failed'

/** 안드로이드 공유 창으로 글(원하면 파일도)을 넘긴다. 파일은 앱의 임시 폴더에 쓴 뒤 그 주소를 넘긴다 */
export async function shareWithApp(text: string, file: File | null): Promise<AppShareResult> {
  try {
    let files: string[] | undefined
    if (file !== null) {
      const path = `공유/${file.name}`
      await writeNativeBytes(Filesystem, path, Directory.Cache, new Uint8Array(await file.arrayBuffer()))
      files = [(await Filesystem.getUri({ path, directory: Directory.Cache })).uri]
    }
    await Share.share({ text, files, dialogTitle: '보낼 앱 고르기' })
    return 'shared'
  } catch (error) {
    // 공유 창을 닫으면 앱이 ‘Share canceled’ 오류를 낸다
    return /cancel/i.test(error instanceof Error ? error.message : String(error)) ? 'cancelled' : 'failed'
  }
}
