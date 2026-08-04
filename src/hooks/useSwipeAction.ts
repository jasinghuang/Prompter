import { useCallback, useRef, useState, type TouchEvent } from 'react';

// Swipe thresholds（拖动限制 / 提交阈值 / 视觉揭示阈值）
export const SWIPE_LIMIT_RIGHT = 72;
export const SWIPE_LIMIT_LEFT = -150;
export const COMMIT_FILMED_PX = 40;
export const COMMIT_DELETE_PX = -130;
export const REVEAL_FILMED_PX = 20;
export const REVEAL_DELETE_PX = -20;

interface Options {
  /** 右滑提交（标记已拍摄） */
  onCommitRight: () => void;
  /** 左滑阶段2提交（删除） */
  onCommitLeft: () => void;
}

/**
 * 单卡滑动手势：管理 offset / shaking 状态 + touch handlers。
 * 状态下沉到单卡，滑动时只重渲染该卡，不触发列表级重渲染（CF3）。
 * 逻辑从 ScriptList 抽出，可独立测试（CF9）。
 */
export function useSwipeAction({ onCommitRight, onCommitLeft }: Options) {
  const [offset, setOffset] = useState(0);
  const [shaking, setShaking] = useState(false);
  const offsetRef = useRef(0);
  const startRef = useRef({ x: 0, y: 0 });
  const swipingRef = useRef(false);
  const shookRef = useRef(false);
  const commitRightRef = useRef(onCommitRight);
  const commitLeftRef = useRef(onCommitLeft);
  commitRightRef.current = onCommitRight;
  commitLeftRef.current = onCommitLeft;

  const update = useCallback((v: number) => {
    offsetRef.current = v;
    setOffset(v);
  }, []);

  const onTouchStart = useCallback((e: TouchEvent) => {
    startRef.current = { x: e.touches[0].clientX, y: e.touches[0].clientY };
    swipingRef.current = true;
    shookRef.current = false;
  }, []);

  const onTouchMove = useCallback((e: TouchEvent) => {
    if (!swipingRef.current) return;
    const dx = e.touches[0].clientX - startRef.current.x;
    const dy = e.touches[0].clientY - startRef.current.y;
    if (Math.abs(dy) > Math.abs(dx)) return; // 忽略纵向滚动
    const clamped = Math.max(SWIPE_LIMIT_LEFT, Math.min(SWIPE_LIMIT_RIGHT, dx));
    update(clamped);
    if (clamped <= COMMIT_DELETE_PX && !shookRef.current) {
      shookRef.current = true;
      setShaking(true);
    }
  }, [update]);

  const onTouchEnd = useCallback(() => {
    if (!swipingRef.current) return;
    swipingRef.current = false;
    const cur = offsetRef.current;
    setShaking(false);
    if (cur > COMMIT_FILMED_PX) {
      commitRightRef.current();
      update(0);
    } else if (cur <= COMMIT_DELETE_PX) {
      commitLeftRef.current();
      // 卡片即将卸载，不必回弹
    } else {
      update(0);
    }
  }, [update]);

  const onTouchCancel = useCallback(() => {
    // 系统中断（来电/横竖屏/滚动被抢占）→ 只回弹，不提交
    swipingRef.current = false;
    setShaking(false);
    update(0);
  }, [update]);

  const clearShaking = useCallback(() => setShaking(false), []);

  return {
    offset,
    shaking,
    swipingRef,
    clearShaking,
    bind: { onTouchStart, onTouchMove, onTouchEnd, onTouchCancel },
  };
}
