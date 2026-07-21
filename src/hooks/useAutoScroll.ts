import { useEffect, useRef } from 'react';

interface Options {
  running: boolean;
  /** 每秒位移的像素数 */
  pxPerSec: number;
  getViewport: () => HTMLElement | null;
  getMaxOffset: () => number;
  onTick: (scrollTop: number) => void;
  onReachEnd: () => void;
}

/**
 * 自动滚动：用 requestAnimationFrame 更新 viewport.scrollTop，
 * 走浏览器原生滚动通道，与手动拖拽共享同一 scrollTop，无缝切换。
 */
export function useAutoScroll({ running, pxPerSec, getViewport, getMaxOffset, onTick, onReachEnd }: Options) {
  const onTickRef = useRef(onTick);
  onTickRef.current = onTick;
  const onReachEndRef = useRef(onReachEnd);
  onReachEndRef.current = onReachEnd;
  const scrollRef = useRef(0);

  useEffect(() => {
    if (!running || pxPerSec <= 0) return;

    const raf =
      typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : (cb: FrameRequestCallback) => setTimeout(() => cb(performance.now()), 16) as unknown as number;
    const caf =
      typeof cancelAnimationFrame === 'function'
        ? cancelAnimationFrame
        : (id: number) => clearTimeout(id);

    let last = performance.now();
    let id = 0;
    let ended = false;

    const tick = (now: number) => {
      const vp = getViewport();
      if (vp) {
        const delta = now - last;
        last = now;
        const max = getMaxOffset();
        let next = scrollRef.current + (pxPerSec * delta) / 1000;
        if (next >= max) {
          vp.scrollTop = max;
          scrollRef.current = max;
          onTickRef.current(max);
          if (!ended) {
            ended = true;
            onReachEndRef.current();
          }
          return;
        }
        vp.scrollTop = next;
        scrollRef.current = next;
        onTickRef.current(next);
      }
      id = raf(tick);
    };

    id = raf(tick);
    return () => caf(id);
  }, [running, pxPerSec, getViewport, getMaxOffset]);

  return scrollRef;
}
