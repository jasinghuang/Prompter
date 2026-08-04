import { useEffect, useRef } from 'react';

interface Options {
  isPlaying: boolean;
  activeIndex: number;
  content: string;
  keyword: string;
  /** 命中时回调（通常: 停止播放 + 提示） */
  onPause: (msg: string) => void;
}

/**
 * 自动暂停：播放过程中遇到关键词则暂停（CF10，从 Teleprompter 抽出）。
 * 同一关键词只触发一次（用 pausedAtRef 记录已命中的绝对位置）。
 */
export function usePauseOnKeyword({ isPlaying, activeIndex, content, keyword, onPause }: Options) {
  const pausedAtRef = useRef(-1);
  const onPauseRef = useRef(onPause);
  onPauseRef.current = onPause;

  // 关键词变更 → 重置命中记录
  useEffect(() => {
    pausedAtRef.current = -1;
  }, [keyword]);

  useEffect(() => {
    if (!isPlaying || !keyword) return;
    const ctxStart = Math.max(0, activeIndex - Math.max(keyword.length, 30));
    const ctx = content.substring(ctxStart, activeIndex + keyword.length);
    const skipOffset = pausedAtRef.current >= ctxStart ? pausedAtRef.current - ctxStart + 1 : 0;
    const idx = ctx.indexOf(keyword, skipOffset);
    if (idx !== -1) {
      const absIdx = ctxStart + idx;
      pausedAtRef.current = absIdx;
      onPauseRef.current(`已暂停：命中关键词「${keyword}」`);
    }
  }, [activeIndex, isPlaying, content, keyword]);
}
