/**
 * 注册 Service Worker。不支持 SW 的环境静默跳过；注册失败不抛错，
 * 以免影响应用主体功能。仅在 production 调用（见 main.tsx）。
 */
export async function registerSW(swUrl: string): Promise<void> {
  if (!('serviceWorker' in navigator)) return;
  try {
    await navigator.serviceWorker.register(swUrl);
  } catch {
    // 注册失败不影响应用使用
  }
}
