import { Check, Edit3, Trash2, X } from 'lucide-react';
import { Script } from '../types';
import {
  useSwipeAction,
  SWIPE_LIMIT_RIGHT,
  REVEAL_FILMED_PX,
  REVEAL_DELETE_PX,
  COMMIT_DELETE_PX,
} from '../hooks/useSwipeAction';

interface Props {
  script: Script;
  isFilmed: boolean;
  charCount: number;
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onToggleFilmed: (id: string) => void;
}

export function SwipeableCard({ script, isFilmed, charCount, onOpen, onEdit, onDelete, onToggleFilmed }: Props) {
  const { offset: swipeX, shaking, swipingRef, clearShaking, bind } = useSwipeAction({
    onCommitRight: () => onToggleFilmed(script.id),
    onCommitLeft: () => onDelete(script.id),
  });

  return (
    <div
      className={`group relative overflow-hidden rounded-2xl border transition-colors duration-200 ${isFilmed
        ? 'border-green-500/30 bg-green-500/[0.06]'
        : 'border-[#D4A432]/15 glass-card hover:border-[#D4A432]/50 hover:bg-white/[0.07]'
      }${shaking ? ' swipe-shake' : ''}`}
      onAnimationEnd={clearShaking}
      {...bind}
    >
      {/* Filmed indicators — fixed, do not slide with content */}
      {isFilmed && (
        <div className="absolute inset-y-0 left-0 z-10 w-[3px] rounded-l-2xl bg-green-500" />
      )}
      {isFilmed && swipeX === 0 && (
        <div className="absolute bottom-3 right-3 z-10 flex items-center gap-1.5 rounded-full border border-green-500/25 bg-green-500/15 px-2 py-0.5 backdrop-blur-sm">
          <span className="h-1.5 w-1.5 rounded-full bg-green-500" />
          <span className="text-[10px] font-semibold text-green-400">已拍摄</span>
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
        className="relative p-4"
        style={{
          transform: `translateX(${swipeX}px)`,
          background: swipeX !== 0 ? '#131316' : undefined,
          transition: swipingRef.current ? 'none' : 'transform 0.25s ease-out',
        }}
        onClick={() => {
          if (swipingRef.current) return;
          onOpen(script.id);
        }}
      >
        {/* Title Row */}
        <div className="mb-2 flex items-start justify-between">
          <div className="flex items-center gap-2 min-w-0">
            {isFilmed && (
              <span className="flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-green-500 text-[10px] font-bold leading-none text-[#0A0A0B]">✓</span>
            )}
            <h3 className={`truncate text-base font-semibold ${isFilmed ? 'text-white/50 line-through' : 'text-white'}`}>{script.title}</h3>
          </div>
          {/* Action buttons — always visible with glass backgrounds */}
          <div className="flex shrink-0 gap-1.5 ml-2">
            <button
              onClick={(e) => { e.stopPropagation(); onEdit(script.id); }}
              className="flex items-center justify-center rounded-lg bg-white/10 px-2.5 py-1.5 text-xs text-white/60 transition-colors hover:bg-white/20 hover:text-white active:scale-95"
              aria-label="编辑稿件"
            >
              <Edit3 size={13} />
            </button>
            <button
              data-testid={`delete-${script.id}`}
              onClick={(e) => { e.stopPropagation(); onDelete(script.id); }}
              className="flex items-center justify-center rounded-lg bg-red-500/15 px-2.5 py-1.5 text-xs text-red-400 transition-colors hover:bg-red-500/25 hover:text-red-300 active:scale-95"
              aria-label="删除稿件"
            >
              <Trash2 size={13} />
            </button>
          </div>
        </div>

        {script.content && (
          <p className={`mb-3 line-clamp-2 text-sm leading-relaxed ${isFilmed ? 'text-white/20 line-through' : 'text-white/40'}`}>{script.content}</p>
        )}

        <div className="flex items-center gap-2 text-[10px] text-white/25">
          {new Date(script.updatedAt).toLocaleDateString()}
          <span>|</span>
          <span>{charCount}字</span>
        </div>
      </div>
    </div>
  );
}
