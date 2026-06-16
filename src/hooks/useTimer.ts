import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * 墙钟计时器。start 起算、stop 停、reset 归零。
 * elapsedSeconds 每秒更新一次（向下取整显示用）。
 */
export function useTimer() {
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const clear = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  }, []);

  const start = useCallback(() => {
    clear();
    intervalRef.current = setInterval(() => {
      setElapsedSeconds((s) => s + 1);
    }, 1000);
  }, [clear]);

  const stop = useCallback(() => {
    clear();
  }, [clear]);

  const reset = useCallback(() => {
    clear();
    setElapsedSeconds(0);
  }, [clear]);

  useEffect(() => clear, [clear]);

  return { elapsedSeconds, start, stop, reset };
}
