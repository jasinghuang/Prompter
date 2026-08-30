import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ArrowUp, ChevronLeft, CirclePause, Edit3, Settings } from 'lucide-react';
import { Script, TeleprompterSettings } from '../types';
import { countReadableChars } from '../lib/tokens';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';
import { formatTime } from '../lib/format';
import { useTimer } from '../hooks/useTimer';
import { useAutoScroll } from '../hooks/useAutoScroll';
import { usePauseOnKeyword } from '../hooks/usePauseOnKeyword';
import { usePauseOnParagraph } from '../hooks/usePauseOnParagraph';
import { useWakeLock } from '../hooks/useWakeLock';
import { useTransientFlag } from '../hooks/useTransientFlag';
import { computePinchFontSize } from '../lib/pinch';
import { ScriptText } from './ScriptText';
import { Controls } from './Controls';
import { SettingsPanel } from './SettingsPanel';

interface Props {
  script: Script;
  settings: TeleprompterSettings;
  index: number;
  onIndexChange: (i: number) => void;
  onChangeSettings: (patch: Partial<TeleprompterSettings>) => void;
  onBack: () => void;
  onEdit: () => void;
  onCompleted: () => void;
}

const ONBOARD_KEY = 'prompter_onboarded';

function hasOnboarded(): boolean {
  try {
    return localStorage.getItem(ONBOARD_KEY) === '1';
  } catch {
    return false;
  }
}

function markOnboarded(): void {
  try {
    localStorage.setItem(ONBOARD_KEY, '1');
  } catch {
    /* noop */
  }
}

export function Teleprompter({
  script,
  settings,
  index,
  onIndexChange,
  onChangeSettings,
  onBack,
  onEdit,
  onCompleted,
}: Props) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(() => !hasOnboarded());
  const [wakeLockFailed, showWakeLockFailed] = useTransientFlag(3000);
  const [pauseReason, setPauseReason] = useState<string | null>(null);
  const pauseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [completed, setCompleted] = useState(false);
  const completionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showPauseToast = useCallback((msg: string) => {
    setPauseReason(msg);
    if (pauseTimerRef.current) clearTimeout(pauseTimerRef.current);
    pauseTimerRef.current = setTimeout(() => setPauseReason(null), 3000);
  }, []);

  useEffect(() => {
    return () => {
      if (pauseTimerRef.current) clearTimeout(pauseTimerRef.current);
      if (completionTimerRef.current) clearTimeout(completionTimerRef.current);
      if (pinchToastTimerRef.current) clearTimeout(pinchToastTimerRef.current);
    };
  }, []);

  const [widthTick, setWidthTick] = useState(0);
  const [activeIndex, setActiveIndex] = useState(index);
  const activeIndexRef = useRef(index);
  const [maxOffset, setMaxOffset] = useState(0);
  const maxOffsetRef = useRef(0);
  const [atBottom, setAtBottom] = useState(false);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  const touchStartRef = useRef<{ y: number } | null>(null);
  // 双指捏合：活跃手指 Map + 手势起始快照 + 轻点抑制冷却
  const pointersRef = useRef<Map<number, { x: number; y: number; t: number }>>(new Map());
  const pinchRef = useRef<{ startDist: number; startFontSize: number } | null>(null);
  const suppressTapUntilRef = useRef(0);
  const [pinchFontSize, setPinchFontSize] = useState<number | null>(null);
  const pinchToastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);

  const { elapsedSeconds, start: startTimer, stop: stopTimer } = useTimer();
  const { request, release } = useWakeLock();

  const computeActive = useCallback((scrollTop: number) => {
    const vp = viewportRef.current;
    if (!vp) return;
    const mid = scrollTop + vp.clientHeight / 2;
    const spans = spansRef.current;
    let idx = -1;
    for (const s of spans) {
      if (s.offsetTop + s.offsetHeight / 2 >= mid) {
        idx = Number(s.dataset.idx);
        break;
      }
    }
    if (idx === -1 && spans.length) idx = Number(spans[spans.length - 1].dataset.idx);
    if (idx >= 0 && idx !== activeIndexRef.current) {
      activeIndexRef.current = idx;
      setActiveIndex(idx);
    }
  }, []);

  useLayoutEffect(() => {
    const vp = viewportRef.current;
    const ct = contentRef.current;
    if (!vp || !ct) return;
    const measure = () => {
      spansRef.current = Array.from(ct.querySelectorAll<HTMLElement>('span[data-idx]'));
      const max = Math.max(0, ct.scrollHeight - vp.clientHeight);
      maxOffsetRef.current = max;
      setMaxOffset(max);
      setAtBottom(max > 0 && vp.scrollTop >= max - 8);
      const target = spansRef.current.find((s) => Number(s.dataset.idx) === activeIndexRef.current);
      if (target) {
        vp.scrollTop = target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2;
        scrollRef.current = vp.scrollTop;
      }
    };
    measure();
    if (typeof ResizeObserver !== 'undefined') {
      const ro = new ResizeObserver(measure);
      ro.observe(ct);
      ro.observe(vp);
      return () => ro.disconnect();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [script.content, settings.fontSize, settings.letterSpacing, settings.lineHeight, settings.horizontalPadding, widthTick]);

  const pxPerSec =
    charCount > 0 && maxOffset > 0
      ? (maxOffset / charCount) * (settings.scrollSpeed / 60)
      : 0;

  const getViewport = useCallback(() => viewportRef.current, []);
  const getMaxOffset = useCallback(() => maxOffsetRef.current, []);

  const scrollToIndex = useCallback((i: number) => {
    const vp = viewportRef.current;
    if (!vp) return;
    if (i === 0) {
      // 开头即顶部，不依赖 span 定位（内容可能以换行开头，无 data-idx=0 的 span）
      vp.scrollTop = 0;
      scrollRef.current = 0;
    } else {
      const target = spansRef.current.find((s) => Number(s.dataset.idx) === i);
      if (target) {
        vp.scrollTop = target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2;
        scrollRef.current = vp.scrollTop;
      }
    }
    activeIndexRef.current = i;
    setActiveIndex(i);
  }, []);

  const scrollRef = useAutoScroll({
    running: isPlaying,
    pxPerSec,
    getViewport,
    getMaxOffset,
    onTick: computeActive,
    onReachEnd: () => {
      if (completed) return; // 深度防御：useAutoScroll 的 ended 标志已保证单次播放周期触发一次
      setIsPlaying(false);
      if (settings.completeAction === 'restart') {
        resetKeywordPause(); // 重读时自动暂停重新生效
        resetParagraphPause();
        scrollToIndex(0); // 回到开头并暂停，不标记/不提示/不返回
        return;
      }
      if (settings.completeAction !== 'list') return; // none：读完即停，不提示/不标记/不返回
      setCompleted(true);
      onCompleted();
      if (completionTimerRef.current) clearTimeout(completionTimerRef.current);
      completionTimerRef.current = setTimeout(() => onBack(), 1200);
    },
  });

  useEffect(() => {
    const check = () => setWidthTick((t) => t + 1);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  useEffect(() => {
    scrollToIndex(index);
  }, [index, scrollToIndex]);

  useEffect(() => {
    const vp = viewportRef.current;
    if (!vp) return;
    const onScroll = () => {
      scrollRef.current = vp.scrollTop;
      computeActive(vp.scrollTop);
      const max = maxOffsetRef.current;
      setAtBottom(max > 0 && vp.scrollTop >= max - 8); // 8px 容差兼容 iOS 橡皮筋回弹
    };
    vp.addEventListener('scroll', onScroll, { passive: true });
    return () => vp.removeEventListener('scroll', onScroll);
  }, [computeActive]);

  const paragraphStarts = useMemo(() => {
    const starts = new Set<number>();
    const chars = Array.from(script.content);
    for (let i = 1; i < chars.length; i++) {
      if (chars[i] === '\n' && chars[i - 1] === '\n') {
        let j = i + 1;
        while (j < chars.length && chars[j] === '\n') j++;
        if (j < chars.length) starts.add(j);
      }
    }
    return starts;
  }, [script.content]);

  const handlePause = useCallback((msg: string) => {
    setIsPlaying(false);
    showPauseToast(msg);
  }, [showPauseToast]);

  const resetKeywordPause = usePauseOnKeyword({
    isPlaying,
    activeIndex,
    content: script.content,
    keyword: settings.pauseKeyword,
    onPause: handlePause,
  });
  const resetParagraphPause = usePauseOnParagraph({
    isPlaying,
    activeIndex,
    paragraphStarts,
    enabled: settings.pauseOnParagraph,
    onPause: handlePause,
  });

  const dismissOnboarding = useCallback(() => {
    setShowOnboarding(false);
    markOnboarded();
  }, []);

  useEffect(() => {
    if (!showOnboarding) return;
    const t = setTimeout(dismissOnboarding, 5000);
    return () => clearTimeout(t);
  }, [showOnboarding, dismissOnboarding]);

  useEffect(() => {
    let cancelled = false;
    request()
      .then(() => { if (cancelled) release(); }) // 卸载发生在 request 飞行中 → 释放刚拿到的 sentinel，避免泄漏
      .catch(() => showWakeLockFailed());
    return () => {
      cancelled = true;
      release();
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (isPlaying) {
      startTimer();
    } else {
      stopTimer();
    }
  }, [isPlaying]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      const btn = (e.target as HTMLElement | null)?.closest('button');
      if (btn) btn.blur();
    };
    window.addEventListener('click', onClick, true);
    return () => window.removeEventListener('click', onClick, true);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === 'Escape') {
        if (showSettings) { setShowSettings(false); return; }
      }
      if (e.code === 'Space') {
        if (showSettings) return;
        if (e.repeat) return;
        e.preventDefault();
        setIsPlaying((p) => !p);
        return;
      }
      if (e.code === 'ArrowUp' || e.code === 'ArrowDown') {
        const t = e.target as HTMLElement | null;
        if (t && t.tagName === 'INPUT') return;
        e.preventDefault();
        const step = e.shiftKey ? 5 : 20;
        const delta = (e.code === 'ArrowUp' ? 1 : -1) * step;
        const next = Math.min(SPEED_MAX, Math.max(SPEED_MIN, settings.scrollSpeed + delta));
        onChangeSettings({ scrollSpeed: next });
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onChangeSettings, settings.scrollSpeed]);

  const handleBack = () => {
    onIndexChange(activeIndexRef.current);
    onBack();
  };
  const handleBackToTop = () => {
    setIsPlaying(false);
    scrollToIndex(0);
  };
  const handleEdit = () => {
    onIndexChange(activeIndexRef.current);
    onEdit();
  };

  /** 手指离开/抬起/取消时统一收尾：移除手指、结束捏合、安排反馈胶囊隐藏 */
  const releasePointer = useCallback((e: React.PointerEvent) => {
    const wasPinching = pinchRef.current !== null;
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2) pinchRef.current = null;
    if (wasPinching) {
      if (pinchToastTimerRef.current) clearTimeout(pinchToastTimerRef.current);
      pinchToastTimerRef.current = setTimeout(() => setPinchFontSize(null), 600);
    }
    return wasPinching;
  }, []);

  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    touchStartRef.current = { y: e.clientY };
    const now = Date.now();
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY, t: now });
    const pointers = [...pointersRef.current.values()];
    if (pointers.length >= 2) {
      const oldest = pointers.reduce((a, b) => (a.t < b.t ? a : b));
      if (now - oldest.t > 500) {
        // 自愈：最旧手指过老（抬起事件丢失，如系统手势抢占），清空只保留新手势
        pointersRef.current.clear();
        pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY, t: now });
        pinchRef.current = null;
        return;
      }
    }
    if (pointersRef.current.size === 2) {
      const [a, b] = [...pointersRef.current.values()];
      pinchRef.current = {
        startDist: Math.hypot(a.x - b.x, a.y - b.y),
        startFontSize: settings.fontSize,
      };
      suppressTapUntilRef.current = Date.now() + 500; // 捏合后短暂抑制轻点切换播放
    }
  }, [settings.fontSize]);

  const handlePointerMove = useCallback((e: React.PointerEvent) => {
    if (!pointersRef.current.has(e.pointerId)) return;
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY, t: Date.now() });
    const pinch = pinchRef.current;
    if (!pinch || pointersRef.current.size < 2) return;
    const [a, b] = [...pointersRef.current.values()];
    const dist = Math.hypot(a.x - b.x, a.y - b.y);
    if (Math.abs(dist - pinch.startDist) < 12) return; // 死区：轻点误判防护
    const next = computePinchFontSize(dist, pinch.startDist, pinch.startFontSize);
    setPinchFontSize(next);
    onChangeSettings({ fontSize: next });
  }, [onChangeSettings]);

  const handlePointerCancel = useCallback((e: React.PointerEvent) => {
    releasePointer(e);
  }, [releasePointer]);

  const handlePointerLeave = useCallback((e: React.PointerEvent) => {
    releasePointer(e);
  }, [releasePointer]);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    if (releasePointer(e)) return;
    const start = touchStartRef.current;
    touchStartRef.current = null;
    if (!start) return;
    if (Date.now() < suppressTapUntilRef.current) return;
    if (Math.abs(e.clientY - start.y) > 8) return;
    setIsPlaying((p) => !p);
  }, [releasePointer]);

  const pad = `${settings.horizontalPadding}%`;

  return (
    <div className="relative h-[100dvh] w-screen overflow-hidden bg-[#0A0A0B]">
      {/* ── Onboarding Overlay ── */}
      {showOnboarding && (
        <div
          className="absolute inset-0 z-[80] flex items-center justify-center bg-[#0A0A0B]/80 backdrop-blur-sm"
          onClick={dismissOnboarding}
        >
          <div className="flex flex-col items-center gap-4 text-center">
            <span className="text-xl font-bold text-[#F5F5F5]">提词器</span>
            <div className="space-y-2.5 text-sm text-[#A1A1AA]">
              <p>
                轻点屏幕{' '}
                <span className="font-medium text-[#F5F5F5]">开始 / 暂停</span>
              </p>
              <p>
                拖动文本{' '}
                <span className="font-medium text-[#F5F5F5]">回看上文</span>
              </p>
              <p>
                空格键{' '}
                <span className="font-medium text-[#F5F5F5]">快捷控制</span>
              </p>
            </div>
            <span className="mt-2 text-xs text-[#71717A]">点击任意位置开始</span>
          </div>
        </div>
      )}

      {/* ── Top Toolbar ── */}
      <div
        className="absolute inset-x-0 top-0 z-50 flex items-center justify-between pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))]"
        style={{
          paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))',
          paddingRight: 'calc(0.75rem + env(safe-area-inset-right))',
        }}
      >
        <div className="flex items-center gap-2">
          <button
            onClick={handleBack}
            className="glass-button flex items-center justify-center rounded-full p-2 text-white/50 hover:text-white active:scale-95"
            aria-label="返回"
            style={{ minHeight: '44px', minWidth: '44px' }}
          >
            <ChevronLeft size={20} />
          </button>

          {/* Timer + Status Indicator — equal-size container */}
          <div className="flex items-center gap-1.5 rounded-full glass-button px-3 py-1.5">
            <span className="flex h-4 w-4 items-center justify-center">
              {isPlaying ? (
                <span className="relative flex h-2.5 w-2.5">
                  <span className="absolute inset-0 rounded-full" style={{ background: 'var(--color-danger)', boxShadow: 'var(--shadow-record)' }} />
                </span>
              ) : (
                <CirclePause size={10} className="text-white/30" />
              )}
            </span>
            <span className="font-mono text-xs tabular-nums text-white/50">
              {formatTime(elapsedSeconds)}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-1">
          <button
            onClick={handleEdit}
            className="glass-button flex items-center justify-center rounded-full p-2 text-white/50 hover:text-white active:scale-95"
            aria-label="编辑"
            style={{ minHeight: '44px', minWidth: '44px' }}
          >
            <Edit3 size={20} />
          </button>
          <button
            onClick={() => setShowSettings(true)}
            className="glass-button flex items-center justify-center rounded-full p-2 text-white/50 hover:text-white active:scale-95"
            aria-label="设置"
            style={{ minHeight: '44px', minWidth: '44px' }}
          >
            <Settings size={20} />
          </button>
        </div>
      </div>

      {/* ── Reading Guide Lines (soft glass) ── */}
      <div
        className="pointer-events-none absolute top-1/2 z-10 -translate-y-1/2"
        style={{ left: 'calc(0.75rem + env(safe-area-inset-left))' }}
      >
        <div className="h-28 w-1 rounded-full" style={{ background: '#D4A432', boxShadow: '0 0 12px 1px rgba(212,164,50,0.55)' }} />
      </div>
      <div
        className="pointer-events-none absolute top-1/2 z-10 -translate-y-1/2"
        style={{ right: 'calc(0.75rem + env(safe-area-inset-right))' }}
      >
        <div className="h-28 w-1 rounded-full" style={{ background: '#D4A432', boxShadow: '0 0 12px 1px rgba(212,164,50,0.55)' }} />
      </div>

      {/* ── Reading Viewport ── */}
      <div
        ref={viewportRef}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
        onPointerMove={handlePointerMove}
        onPointerCancel={handlePointerCancel}
        onPointerLeave={handlePointerLeave}
        className={`teleprompter-touch absolute inset-0 z-0 overflow-y-auto ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
          textAlign: settings.textAlign,
          paddingLeft: pad,
          paddingRight: pad,
          WebkitOverflowScrolling: 'touch',
        }}
      >
        <div ref={contentRef} className="mx-auto max-w-[56rem] pb-[25vh] pt-[16vh]">
          <ScriptText content={script.content} />
        </div>
      </div>

      {/* ── Bottom Controls ── */}
      <Controls
        visible={!isPlaying}
        isPlaying={isPlaying}
        onTogglePlay={() => setIsPlaying((p) => !p)}
        fontSize={settings.fontSize}
        speed={settings.scrollSpeed}
        onFontSizeChange={(v) => onChangeSettings({ fontSize: v })}
        onSpeedChange={(v) => onChangeSettings({ scrollSpeed: v })}
      />

      {/* ── Back To Top（停在最底部且暂停时出现） ── */}
      {atBottom && !isPlaying && (
        <button
          onClick={handleBackToTop}
          aria-label="回到顶部"
          className="absolute inset-x-0 bottom-[calc(13rem+env(safe-area-inset-bottom))] z-40 mx-auto flex w-fit items-center gap-1.5 rounded-full border border-white/10 glass-surface px-4 py-2.5 text-xs text-white/80 transition-all hover:text-white active:scale-95"
        >
          <ArrowUp size={14} />
          回到顶部
        </button>
      )}

      {/* ── Wake Lock Failed Toast ── */}
      {wakeLockFailed && (
        <div className="absolute inset-x-0 bottom-36 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-[#D4A432]">
          当前设备无法自动保持常亮，请在系统设置中调长自动锁屏
        </div>
      )}

      {/* ── Pause Reason Toast ── */}
      {pauseReason && (
        <div className="absolute inset-x-0 top-20 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-[#D4A432]">
          {pauseReason}
        </div>
      )}

      {/* ── Pinch Font Size Feedback ── */}
      {pinchFontSize !== null && (
        <div className="absolute inset-x-0 top-20 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-[#D4A432]">
          字号 {pinchFontSize}px
        </div>
      )}

      {/* ── Completed Notice ── */}
      {completed && (
        <div className="absolute inset-x-0 top-20 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-green-400">
          ✓ 已读完·已标记拍摄
        </div>
      )}

      {/* ── Settings Panel ── */}
      <SettingsPanel
        open={showSettings}
        settings={settings}
        onChange={onChangeSettings}
        onClose={() => setShowSettings(false)}
      />
    </div>
  );
}
