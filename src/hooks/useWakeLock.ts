import { useCallback, useRef } from 'react';

interface WakeLockSentinel {
  released: boolean;
  release: () => Promise<void>;
}
interface NavigatorWakeLock {
  request(type: 'screen'): Promise<WakeLockSentinel>;
}

export function useWakeLock() {
  const sentinelRef = useRef<WakeLockSentinel | null>(null);

  const request = useCallback(async () => {
    const wl = (navigator as unknown as { wakeLock?: NavigatorWakeLock }).wakeLock;
    if (!wl) throw new Error('Wake Lock 不被当前环境支持');
    const sentinel = await wl.request('screen');
    sentinelRef.current = sentinel;
  }, []);

  const release = useCallback(async () => {
    const s = sentinelRef.current;
    sentinelRef.current = null;
    if (s && !s.released) {
      try { await s.release(); } catch { /* 已释放则忽略 */ }
    }
  }, []);

  return { request, release };
}
