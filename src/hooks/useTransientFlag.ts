import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * 短暂状态标记：调用 trigger() 将标记置为 true，duration ms 后自动重置为 false。
 * 多次调用 trigger 会重置计时器；组件卸载时自动清理 timer 避免 setState on unmounted。
 */
export function useTransientFlag(duration = 3000): [boolean, () => void] {
  const [flag, setFlag] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const trigger = useCallback(() => {
    setFlag(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setFlag(false), duration);
  }, [duration]);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  return [flag, trigger];
}
