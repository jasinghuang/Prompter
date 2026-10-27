import { useCallback, useEffect, useRef, useState } from 'react';
import { Check, Edit3, Folder, Star, Trash2, X } from 'lucide-react';
import { Script, DEFAULT_SETTINGS } from '../types';
import { estimateDurationSeconds } from '../lib/speed';
import { formatTime } from '../lib/format';
import {
  useSwipeAction,
  SWIPE_LIMIT_RIGHT,
  REVEAL_FILMED_PX,
  REVEAL_DELETE_PX,
  COMMIT_DELETE_PX,
} from '../hooks/useSwipeAction';

/** 长按进入多选的触发时长 */
export const LONG_PRESS_MS = 500;
/** 长按容忍位移（超过视为拖动/滑动，取消长按） */
const LONG_PRESS_SLOP = 10;

interface Props {
  script: Script;
  isFilmed: boolean;
  charCount: number;
  /** 滚动速度（字/分），用于估算口播时长 */
  speed?: number;
  starred?: boolean;
  /** 最近打开（返回列表时金边微光定位） */
  highlighted?: boolean;
  /** 多选模式：点击=切换选中，禁用滑动与内部按钮 */
  selectMode?: boolean;
  isSelected?: boolean;
  onToggleSelect?: (id: string) => void;
  /** 长按触发（进入多选并选中本卡） */
  onLongPress?: (id: string) => void;
  onToggleStar?: () => void;
  /** 打开「移动到文件夹」弹层 */
  onOpenFolderPicker?: () => void;
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onToggleFilmed: (id: string) => void;
}

export function SwipeableCard({ script, isFilmed, charCount, speed = DEFAULT_SETTINGS.scrollSpeed, starred, highlighted, selectMode, isSelected, onToggleSelect, onLongPress, onToggleStar, onOpenFolderPicker, onOpen, onEdit, onDelete, onToggleFilmed }: Props) {
  // 删除退场：先播放收起动画，动画结束才真正 onDelete（配合上层撤销机制）
  const [exiting, setExiting] = useState(false);
  const beginExit = useCallback(() => setExiting(true), []);

  const { offset: swipeX, shaking, swipingRef, clearShaking, bind } = useSwipeAction({
    onCommitRight: () => onToggleFilmed(script.id),
    onCommitLeft: beginExit,
  });

  // 长按进入多选：按下起计时，位移超限/松手/系统取消即掐掉；触发后抑制随后的 click
  const longPressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const longPressFiredRef = useRef(false);
  const pressStartRef = useRef<{ x: number; y: number } | null>(null);

  const cancelLongPress = useCallback(() => {
    if (longPressTimerRef.current) {
      clearTimeout(longPressTimerRef.current);
      longPressTimerRef.current = null;
    }
    pressStartRef.current = null;
  }, []);

  useEffect(() => cancelLongPress, [cancelLongPress]);

  const handleRootPointerDown = useCallback((e: React.PointerEvent) => {
    if (selectMode || exiting) return;
    pressStartRef.current = { x: e.clientX, y: e.clientY };
    longPressFiredRef.current = false;
    longPressTimerRef.current = setTimeout(() => {
      longPressFiredRef.current = true;
      onLongPress?.(script.id);
    }, LONG_PRESS_MS);
  }, [selectMode, exiting, onLongPress, script.id]);

  const handleRootPointerMove = useCallback((e: React.PointerEvent) => {
    const start = pressStartRef.current;
    if (!start) return;
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) > LONG_PRESS_SLOP) cancelLongPress();
  }, [cancelLongPress]);

  const handleCardClick = () => {
    if (longPressFiredRef.current) {
      longPressFiredRef.current = false; // 长按刚触发，吞掉这次 click
      return;
    }
    if (selectMode) {
      onToggleSelect?.(script.id);
      return;
    }
    if (swipingRef.current) return;
    onOpen(script.id);
  };

  const handleAnimationEnd = () => {
    if (exiting) {
      onDelete(script.id);
      return;
    }
    clearShaking();
  };

  const baseStyle = selectMode && isSelected
    ? 'glass-card border-[#D4A432]/60'
    : isFilmed
      ? 'border-green-500/30 bg-green-500/[0.06]'
      : highlighted
        ? 'glass-card border-[#D4A432]/45 shadow-[0_0_22px_rgba(212,164,50,0.14)]'
        : 'border-[#D4A432]/15 glass-card hover:border-[#D4A432]/50 hover:bg-white/[0.07]';

  return (
    <div
      className={`swipe-card group relative overflow-hidden rounded-2xl border transition-[border-color,background-color,scale] duration-200 active:scale-[0.98] ${baseStyle}${
        highlighted && !(selectMode && isSelected) ? ' card-hello' : ''
      }${shaking ? ' swipe-shake' : ''}${exiting ? ' card-exit' : ''}`}
      onAnimationEnd={handleAnimationEnd}
      onPointerDown={handleRootPointerDown}
      onPointerMove={handleRootPointerMove}
      onPointerUp={cancelLongPress}
      onPointerCancel={cancelLongPress}
      onContextMenu={(e) => e.preventDefault()} // Android 长按会弹系统菜单
      {...(selectMode || exiting ? {} : bind)}
    >
      {/* 多选圈（右上角） */}
      {selectMode && (
        <div
          className={`absolute right-3 top-3 z-20 flex h-[22px] w-[22px] items-center justify-center rounded-full border transition-colors ${
            isSelected ? 'border-[#D4A432] bg-[#D4A432] text-[#0A0A0B]' : 'border-white/30 bg-black/40 text-transparent'
          }`}
          aria-hidden="true"
        >
          <Check size={13} strokeWidth={3} />
        </div>
      )}

      {/* Filmed indicators — fixed, do not slide with content */}
      {isFilmed && (
        <div className="absolute inset-y-0 left-0 z-10 w-[3px] rounded-l-2xl bg-green-500" />
      )}
      {isFilmed && swipeX === 0 && (
        <div className="absolute bottom-2.5 right-3 z-10 flex items-center gap-1.5 rounded-full border border-green-500/25 bg-green-500/15 px-2 py-0.5 backdrop-blur-sm">
          <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
          <span className="text-[11px] font-semibold text-green-400">已拍摄</span>
        </div>
      )}

      {/* Right swipe (→): filmed action on the left */}
      <div className="absolute inset-y-0 left-0 flex w-[72px] items-center justify-center rounded-l-2xl transition-opacity duration-200"
        style={{
          background: swipeX > REVEAL_FILMED_PX ? (isFilmed ? '#52525B' : '#22C55E') : 'transparent',
          opacity: swipeX > REVEAL_FILMED_PX ? 1 : 0,
        }}
      >
        {isFilmed ? (
          <X size={20} strokeWidth={3} className="text-white" />
        ) : (
          <Check size={20} strokeWidth={3} className="text-white" />
        )}
      </div>

      {/* Left swipe hint (←): 阶段1后红区左侧的确认引导（CF13） */}
      <div
        className="absolute inset-y-0 flex items-center justify-center overflow-hidden"
        style={{
          right: '72px',
          width: `${Math.max(0, Math.min(80, -swipeX - 72))}px`,
          background: 'linear-gradient(to left, rgba(220,38,38,0.85), rgba(220,38,38,0.15))',
          opacity: swipeX < -SWIPE_LIMIT_RIGHT ? 1 : 0,
          transition: swipingRef.current ? 'none' : 'opacity 0.2s',
        }}
      >
        <span className="whitespace-nowrap text-[10px] font-bold tracking-wide text-white/95">
          {swipeX <= COMMIT_DELETE_PX ? '松开删除' : '继续滑动'}
        </span>
      </div>

      {/* Left swipe (←): red "删除" on the right */}
      <div className="absolute inset-y-0 right-0 flex w-[72px] items-center justify-center rounded-r-2xl transition-opacity duration-200"
        style={{
          background: swipeX < COMMIT_DELETE_PX ? '#EF4444' : (swipeX < REVEAL_DELETE_PX ? '#DC2626' : 'transparent'),
          opacity: swipeX < REVEAL_DELETE_PX ? 1 : 0,
        }}
      >
        <Trash2 size={20} strokeWidth={2.5} className="text-white transition-transform duration-150"
          style={{ transform: swipeX < COMMIT_DELETE_PX ? 'scale(1.15)' : 'scale(1)' }}
        />
      </div>

      {/* Card content — slides on swipe */}
      <div
        data-testid={`content-${script.id}`}
        className="relative px-4 pb-2.5 pt-3"
        style={{
          transform: `translateX(${swipeX}px)`,
          background: swipeX !== 0 ? '#131316' : undefined,
          transition: swipingRef.current ? 'none' : 'transform 0.25s ease-out',
        }}
        onClick={handleCardClick}
      >
        {/* Title Row */}
        <div className="mb-1.5 flex items-start justify-between">
          <div className="flex items-center gap-2 min-w-0">
            {isFilmed && (
              <span className="flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-green-500 text-[10px] font-bold leading-none text-[#0A0A0B]">✓</span>
            )}
            <h3 className={`truncate text-base font-semibold ${isFilmed ? 'text-white/50 line-through' : 'text-white'}`}>{script.title}</h3>
          </div>
          {/* Action buttons — ghost 样式：默认无底色，悬停才现淡底（多选中隐藏让位给选择圈，保留占位避免卡片高度跳动） */}
          <div className={`flex shrink-0 gap-1 ml-2${selectMode ? ' invisible' : ''}`}>
            <button
              onClick={(e) => { e.stopPropagation(); onEdit(script.id); }}
              className="flex h-[var(--ctl-3-h)] items-center justify-center rounded-lg px-2.5 text-xs text-white/40 transition-colors hover:bg-white/15 hover:text-white active:scale-95"
              aria-label="编辑稿件"
            >
              <Edit3 size={13} />
            </button>
            <button
              data-testid={`delete-${script.id}`}
              onClick={(e) => { e.stopPropagation(); beginExit(); }}
              className="flex h-[var(--ctl-3-h)] items-center justify-center rounded-lg px-2.5 text-xs text-[#D4A432]/70 transition-colors hover:bg-[#D4A432]/15 hover:text-[#D4A432] active:scale-95"
              aria-label="删除稿件"
            >
              <Trash2 size={13} />
            </button>
          </div>
        </div>

        {script.content && (
          <p className={`mb-1.5 line-clamp-2 text-sm leading-relaxed ${isFilmed ? 'text-white/15 line-through' : 'text-white/25'}`}>{script.content}</p>
        )}

        {/* Meta row — T4 元信息（12px）：重量介于标题与正文之间 */}
        <div className="flex items-center gap-2.5 text-xs text-white/50">
          <div className="flex min-w-0 items-center gap-2.5">
            {new Date(script.updatedAt).toLocaleDateString()}
            <span className="text-white/15">|</span>
            <span>{charCount}字</span>
            <span className="text-white/15">|</span>
            <span>约{formatTime(estimateDurationSeconds(charCount, speed))}</span>
          </div>
          <div className={`ml-auto flex shrink-0 items-center gap-1.5${selectMode ? ' pointer-events-none opacity-30' : ''}`}>
            <button
              onClick={(e) => { e.stopPropagation(); onOpenFolderPicker?.(); }}
              aria-label="移动到文件夹"
              className="flex items-center gap-1 rounded-full px-2 py-1.5 transition-colors hover:bg-white/10"
            >
              <Folder size={14} className={script.folder ? 'text-[#D4A432]' : 'text-white/35'} />
              {script.folder && <span className="max-w-[16vw] truncate text-white/50">{script.folder}</span>}            </button>
            <button
              onClick={(e) => { e.stopPropagation(); onToggleStar?.(); }}
              aria-label={starred ? '取消星标' : '星标'}
              className="rounded-full p-1.5 transition-colors hover:bg-white/10"
            >
              <Star
                size={15}
                className={starred ? 'text-[#D4A432]' : 'text-white/35 hover:text-white/50'}
                fill={starred ? '#D4A432' : 'none'}
              />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
