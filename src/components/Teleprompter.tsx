import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { ChevronLeft, CirclePause, Edit3, Settings } from 'lucide-react';
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
    };
  }, []);

  const [widthTick, setWidthTick] = useState(0);
  const [activeIndex, setActiveIndex] = useState(index);
  const activeIndexRef = useRef(index);
  const [maxOffset, setMaxOffset] = useState(0);
  const maxOffsetRef = useRef(0);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  const touchStartRef = useRef<{ y: number } | null>(null);

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

  const scrollRef = useAutoScroll({
    running: isPlaying,
    pxPerSec,
    getViewport,
    getMaxOffset,
    onTick: computeActive,
    onReachEnd: () => {
      if (completed) return; // 深度防御：useAutoScroll 的 ended 标志已保证单次播放周期触发一次
      setIsPlaying(false);
      if (!settings.autoReturnOnComplete) return; // 关：读完即停，不提示/不标记/不返回
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

  const scrollToIndex = useCallback((i: number) => {
    const vp = viewportRef.current;
    if (!vp) return;
    const target = spansRef.current.find((s) => Number(s.dataset.idx) === i);
    if (target) {
      vp.scrollTop = target.offsetTop - vp.clientHeight / 2 + target.offsetHeight / 2;
      scrollRef.current = vp.scrollTop;
    }
    activeIndexRef.current = i;
    setActiveIndex(i);
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

  usePauseOnKeyword({
    isPlaying,
    activeIndex,
    content: script.content,
    keyword: settings.pauseKeyword,
    onPause: handlePause,
  });
  usePauseOnParagraph({
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
  const handleEdit = () => {
    onIndexChange(activeIndexRef.current);
    onEdit();
  };

  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    touchStartRef.current = { y: e.clientY };
  }, []);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const start = touchStartRef.current;
    touchStartRef.current = null;
    if (!start) return;
    if (Math.abs(e.clientY - start.y) > 8) return;
    setIsPlaying((p) => !p);
  }, []);

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
        <div className="h-28 w-0.5 rounded-full bg-white/[0.06]" />
      </div>
      <div
        className="pointer-events-none absolute top-1/2 z-10 -translate-y-1/2"
        style={{ right: 'calc(0.75rem + env(safe-area-inset-right))' }}
      >
        <div className="h-28 w-0.5 rounded-full bg-white/[0.06]" />
      </div>

      {/* ── Reading Viewport ── */}
      <div
        ref={viewportRef}
        onPointerDown={handlePointerDown}
        onPointerUp={handlePointerUp}
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
        <div ref={contentRef} className="mx-auto max-w-[56rem] pb-[18vh] pt-[16vh]">
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
