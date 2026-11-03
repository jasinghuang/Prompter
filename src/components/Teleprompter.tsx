import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Camera, ChevronLeft, CircleCheck, Pause, Play, SlidersHorizontal } from 'lucide-react';
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
import { Capsule, CapsuleButton, CapsuleDivider } from './CapsuleButton';
import { CameraMirror } from './CameraMirror';

interface Props {
  script: Script;
  settings: TeleprompterSettings;
  index: number;
  onIndexChange: (i: number) => void;
  onChangeSettings: (patch: Partial<TeleprompterSettings>) => void;
  onBack: () => void;
  onCompleted: () => void;
  /** 当前稿件是否已标记拍摄 */
  isFilmed: boolean;
  /** 标记/取消标记拍摄（播放页「已完成」按钮） */
  onToggleFilmed: () => void;
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
  onCompleted,
  isFilmed,
  onToggleFilmed,
}: Props) {
  const [isPlaying, setIsPlaying] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showMirror, setShowMirror] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(() => !hasOnboarded());
  const [wakeLockFailed, showWakeLockFailed] = useTransientFlag(3000);
  const [pauseReason, setPauseReason] = useState<string | null>(null);
  // 读完停在末尾时的引导提示（对齐 iOS returnHint）：点击顶栏时间回顶后消失
  const [showReturnHint, setShowReturnHint] = useState(false);
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

  // 离开底部即开始新的浏览回合，读完提示不再成立（对齐 iOS onAtBottom 行为）
  useEffect(() => {
    if (!atBottom) setShowReturnHint(false);
  }, [atBottom]);

  const viewportRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const spansRef = useRef<HTMLElement[]>([]);
  const touchStartRef = useRef<{ y: number } | null>(null);
  // 双指捏合：手势快照存 ref（字号变化触发 effect 重挂载时不丢失）+ 轻点抑制冷却 + 反馈胶囊
  const pinchRef = useRef<{ startDist: number; startFontSize: number } | null>(null);
  const fontSizeRef = useRef(settings.fontSize);
  const suppressTapUntilRef = useRef(0);
  const [pinchFontSize, setPinchFontSize] = useState<number | null>(null);
  const pinchToastTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    fontSizeRef.current = settings.fontSize;
  }, [settings.fontSize]);

  const charCount = useMemo(() => countReadableChars(script.content), [script.content]);

  const { elapsedSeconds, start: startTimer, stop: stopTimer, reset: resetTimer } = useTimer();
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
      if (settings.completeAction !== 'list') {
        // none：读完即停（不标记/不返回），提示条引导点击时间回顶（对齐 iOS）
        setShowReturnHint(true);
        return;
      }
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

  // 调速（键盘 ↑↓）：夹紧范围 + toast 反馈
  const changeSpeed = useCallback((delta: number) => {
    const next = Math.min(SPEED_MAX, Math.max(SPEED_MIN, settings.scrollSpeed + delta));
    onChangeSettings({ scrollSpeed: next });
    showPauseToast(`速度 ${next} 字/分`);
  }, [settings.scrollSpeed, onChangeSettings, showPauseToast]);

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
        changeSpeed(e.code === 'ArrowUp' ? step : -step);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [onChangeSettings, settings.scrollSpeed, showSettings]);

  const handleBack = () => {
    onIndexChange(activeIndexRef.current);
    onBack();
  };
  // 点击顶栏时间=回到顶部（对齐 iOS returnToTop）：暂停、计时归零（新一条开拍）、
  // 重置自动暂停命中、清提示，回正文开头
  const handleBackToTop = () => {
    setIsPlaying(false);
    resetTimer();
    resetKeywordPause();
    resetParagraphPause();
    setPauseReason(null);
    if (pauseTimerRef.current) clearTimeout(pauseTimerRef.current);
    if (completionTimerRef.current) clearTimeout(completionTimerRef.current);
    setShowReturnHint(false);
    scrollToIndex(0);
  };

  const handlePointerDown = useCallback((e: React.PointerEvent) => {
    touchStartRef.current = { y: e.clientY };
  }, []);

  const handlePointerUp = useCallback((e: React.PointerEvent) => {
    const start = touchStartRef.current;
    touchStartRef.current = null;
    if (!start) return;
    if (Date.now() < suppressTapUntilRef.current) return;
    if (Math.abs(e.clientY - start.y) > 8) return;
    setIsPlaying((p) => !p);
  }, []);

  // 双指捏合调字号：原生 touch 事件（React 合成 touchmove 是 passive 无法 preventDefault）。
  // iOS Safari 对 Pointer 多指与 touch-action 的支持不可靠，touch 事件实时反映手指列表。
  useEffect(() => {
    const vp = viewportRef.current;
    if (!vp) return;

    const distOf = (touches: TouchList | Touch[]) => {
      if (touches.length < 2) return 0;
      const a = touches[0];
      const b = touches[1];
      return Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
    };

    const onTouchStart = (e: TouchEvent) => {
      if (e.touches.length === 2) {
        pinchRef.current = { startDist: distOf(e.touches), startFontSize: fontSizeRef.current };
        suppressTapUntilRef.current = Date.now() + 500; // 捏合后短暂抑制轻点切换播放
      }
    };

    const onTouchMove = (e: TouchEvent) => {
      const pinch = pinchRef.current;
      if (e.touches.length < 2 || !pinch) return;
      e.preventDefault(); // 阻止双指期间的页面滚动/缩放
      const dist = distOf(e.touches);
      if (Math.abs(dist - pinch.startDist) < 12) return; // 死区：轻点误判防护
      const next = computePinchFontSize(dist, pinch.startDist, pinch.startFontSize);
      setPinchFontSize(next);
      onChangeSettings({ fontSize: next });
    };

    const onTouchEnd = (e: TouchEvent) => {
      if (e.touches.length < 2 && pinchRef.current) {
        pinchRef.current = null;
        suppressTapUntilRef.current = Date.now() + 500;
        if (pinchToastTimerRef.current) clearTimeout(pinchToastTimerRef.current);
        pinchToastTimerRef.current = setTimeout(() => setPinchFontSize(null), 600);
      }
    };

    vp.addEventListener('touchstart', onTouchStart, { passive: true });
    vp.addEventListener('touchmove', onTouchMove, { passive: false });
    vp.addEventListener('touchend', onTouchEnd);
    vp.addEventListener('touchcancel', onTouchEnd);
    return () => {
      vp.removeEventListener('touchstart', onTouchStart);
      vp.removeEventListener('touchmove', onTouchMove);
      vp.removeEventListener('touchend', onTouchEnd);
      vp.removeEventListener('touchcancel', onTouchEnd);
    };
  }, [onChangeSettings]);

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

      {/* ── Top Bar — 双胶囊（左：导航/状态，右：操作），构造见 CapsuleButton ── */}
      <div
        className="absolute inset-x-0 top-[calc(0.75rem+env(safe-area-inset-top))] z-50 flex items-center gap-2.5 px-4"
        style={{
          paddingLeft: 'calc(1rem + env(safe-area-inset-left))',
          paddingRight: 'calc(1rem + env(safe-area-inset-right))',
        }}
      >
        {/* 左胶囊：返回 + 录制状态/计时（暂停时双竖线，播放中红点）+ 前置镜子 */}
        <Capsule>
          <CapsuleButton label="返回" onClick={handleBack}>
            <ChevronLeft size={18} />
          </CapsuleButton>
          <CapsuleDivider />
          {/* 点击时间=回到顶部：暂停+计时归零+回正文开头（对齐 iOS）；图标 play 金/pause 灰 */}
          <button
            type="button"
            onClick={handleBackToTop}
            aria-label="回到顶部"
            title="回到正文开头（暂停并归零计时）"
            className="flex h-[34px] items-center gap-[7px] rounded-full px-[11px] transition-colors hover:bg-white/10 active:scale-95"
          >
            {/* 播放/暂停状态位：两态同占 12px 盒、icon 居中同尺寸（对齐 iOS play.fill/pause.fill），
                切换时占位与视觉中心完全一致，时间数字不横移 */}
            <span className="flex h-3 w-3 shrink-0 items-center justify-center">
              {isPlaying ? (
                <Play size={10} className="fill-current text-[#D4A432]" />
              ) : (
                <Pause size={10} className="text-white/35" />
              )}
            </span>
            <span className="font-mono text-[13px] tracking-wide tabular-nums text-white/60">
              {formatTime(elapsedSeconds)}
            </span>
          </button>
          <CapsuleDivider />
          <CapsuleButton label="前置镜子" onClick={() => setShowMirror(true)}>
            <Camera size={18} strokeWidth={2.4} />
          </CapsuleButton>
        </Capsule>

        <div className="min-w-0 flex-1" />

        {/* 右胶囊：标记已拍摄 / 设置 —— 播放中自动隐藏（防误触/不抢正文视线）；编辑回列表页做（对齐 iOS） */}
        <div
          className={`transition-all duration-300 ${
            isPlaying ? 'pointer-events-none -translate-y-2 opacity-0' : 'translate-y-0 opacity-100'
          }`}
        >
          <Capsule>
            <CapsuleButton
              label={isFilmed ? '取消已拍摄标记' : '标记为已拍摄'}
              active={isFilmed}
              onClick={() => {
                onToggleFilmed();
                showPauseToast(isFilmed ? '已取消已拍摄标记' : '已标记拍摄 ✓');
              }}
            >
              <CircleCheck size={18} strokeWidth={2.4} />
            </CapsuleButton>
            <CapsuleDivider />
            <CapsuleButton label="设置" onClick={() => setShowSettings(true)}>
              <SlidersHorizontal size={18} strokeWidth={2.4} />
            </CapsuleButton>
          </Capsule>
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
        className={`teleprompter-touch absolute inset-0 z-0 overflow-y-auto ${settings.mirror ? 'mirror-mode' : ''}`}
        style={{
          fontSize: `${settings.fontSize}px`,
          lineHeight: settings.lineHeight,
          letterSpacing: `${settings.letterSpacing}em`,
          textAlign: settings.textAlign,
          paddingLeft: pad,
          paddingRight: pad,
        }}
      >
        <div ref={contentRef} className="mx-auto max-w-[56rem] pb-[18vh] pt-[16vh]">
          <ScriptText content={script.content} />
        </div>
      </div>

      {/* ── Bottom Controls ── */}
      <Controls
        visible={!isPlaying}
        fontSize={settings.fontSize}
        speed={settings.scrollSpeed}
        onFontSizeChange={(v) => onChangeSettings({ fontSize: v })}
        onSpeedChange={(v) => onChangeSettings({ scrollSpeed: v })}
      />

      {/* ── 读完提示（停在末尾模式）：引导点击顶栏时间回顶（对齐 iOS returnHint） ── */}
      {showReturnHint && (
        <div className="pointer-events-none absolute inset-x-0 top-20 z-40 mx-auto w-fit rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-white/55">
          已读完，点击时间回到顶部
        </div>
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

      {/* ── Front Camera Mirror（临时化妆镜，关闭即释放摄像头） ── */}
      <CameraMirror open={showMirror} onClose={() => setShowMirror(false)} />
    </div>
  );
}
