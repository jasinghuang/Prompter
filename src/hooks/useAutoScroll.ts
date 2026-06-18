import { useEffect, useRef } from 'react';

interface Options {
  running: boolean;
  /** 每秒位移的像素数（由 WPN 与每字垂直像素换算） */
  pxPerSec: number;
  getContent: () => HTMLElement | null;
  getMaxOffset: () => number;
  /** 每帧位移后回调最新 offset（供高亮反推） */
  onTick: (offset: number) => void;
  onReachEnd: () => void;
}

/**
 * 自动模式：用 requestAnimationFrame 让内容容器的 transform.translateY 连续匀速变化，
 * 走 GPU 合成层、支持亚像素，任何速度（含极慢）都丝滑无极。
 * 返回 offsetRef，供外部（手动跳转/拖拽）读写同一位移状态。
 */
export function useAutoScroll({ running, pxPerSec, getContent, getMaxOffset, onTick, onReachEnd }: Options) {
  const onTickRef = useRef(onTick);
  onTickRef.current = onTick;
  const onReachEndRef = useRef(onReachEnd);
  onReachEndRef.current = onReachEnd;
  const offsetRef = useRef(0);

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

    const apply = (content: HTMLElement, offset: number) => {
      content.style.transform = `translate3d(0, ${-offset}px, 0)`;
      offsetRef.current = offset;
    };

    const tick = (now: number) => {
      const content = getContent();
      if (content) {
        const delta = now - last;
        last = now;
        const max = getMaxOffset();
        let next = offsetRef.current + (pxPerSec * delta) / 1000;
        if (next >= max) {
          apply(content, max);
          onTickRef.current(max);
          if (!ended) {
            ended = true;
            onReachEndRef.current();
          }
          return; // 到底停止循环
        }
        apply(content, next);
        onTickRef.current(next);
      }
      id = raf(tick);
    };

    id = raf(tick);
    return () => caf(id);
  }, [running, pxPerSec, getContent, getMaxOffset]);

  return offsetRef;
}
