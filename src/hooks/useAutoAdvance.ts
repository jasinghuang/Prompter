import { useEffect, useRef } from 'react';
import { stepAutoAdvance } from '../lib/speed';

interface Options {
  running: boolean;
  wpn: number;
  enabled: boolean;
  onAdvance: (chars: number) => void;
}

/**
 * 自动模式：按 WPN 用 requestAnimationFrame 推进字符数。
 * - running 且 enabled 时启动 rAF 循环
 * - 每帧累加 deltaTime，超过 msPerChar 即回调推进
 */
export function useAutoAdvance({ running, wpn, enabled, onAdvance }: Options) {
  const onAdvanceRef = useRef(onAdvance);
  onAdvanceRef.current = onAdvance;

  useEffect(() => {
    if (!running || !enabled) return;

    const raf =
      typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : (cb: FrameRequestCallback) => setTimeout(() => cb(performance.now()), 16) as unknown as number;
    const caf =
      typeof cancelAnimationFrame === 'function'
        ? cancelAnimationFrame
        : (id: number) => clearTimeout(id);

    let accumulator = 0;
    let last = performance.now();
    let id: number;

    const tick = (now: number) => {
      const delta = now - last;
      last = now;
      const { accumulator: nextAcc, advance } = stepAutoAdvance(accumulator, delta, wpn);
      accumulator = nextAcc;
      if (advance > 0) onAdvanceRef.current(advance);
      id = raf(tick);
    };

    id = raf(tick);
    return () => caf(id);
  }, [running, enabled, wpn]);
}
