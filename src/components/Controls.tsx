import { Type, Gauge } from 'lucide-react';
import { FONT_SIZE_MIN, FONT_SIZE_MAX } from '../types';
import { SPEED_MIN, SPEED_MAX } from '../lib/speed';

interface Props {
  fontSize: number;
  speed: number;
  visible: boolean;
  onFontSizeChange: (v: number) => void;
  onSpeedChange: (v: number) => void;
}

export function Controls({ fontSize, speed, visible, onFontSizeChange, onSpeedChange }: Props) {
  return (
    <div className={`absolute bottom-[calc(0.75rem+env(safe-area-inset-bottom))] left-3 right-3 z-50 flex flex-col gap-2 rounded-2xl border border-neutral-800/40 bg-neutral-900/85 px-3 py-2.5 shadow-2xl backdrop-blur-xl transition-all duration-300 sm:flex-row sm:items-center sm:gap-3 ${
      visible ? 'translate-y-0 opacity-100' : 'translate-y-20 opacity-0 pointer-events-none'
    }`}>
      <div className="flex flex-1 items-center gap-1.5">
        <Type size={14} className="shrink-0 text-neutral-600" />
        <input
          type="range"
          aria-label="字号"
          min={FONT_SIZE_MIN}
          max={FONT_SIZE_MAX}
          step={2}
          value={fontSize}
          onChange={(e) => onFontSizeChange(parseInt(e.target.value, 10))}
          className="h-1 min-w-0 flex-1 accent-yellow-500"
        />
        <span className="w-6 shrink-0 text-right font-mono text-[11px] tabular-nums text-neutral-400">{fontSize}</span>
      </div>
      <div className="flex flex-1 items-center gap-1.5">
        <Gauge size={14} className="shrink-0 text-neutral-600" />
        <input
          type="range"
          aria-label="速度"
          min={SPEED_MIN}
          max={SPEED_MAX}
          step={10}
          value={speed}
          onChange={(e) => onSpeedChange(parseInt(e.target.value, 10))}
          className="h-1 min-w-0 flex-1 accent-yellow-500"
        />
        <span className="w-7 shrink-0 text-right font-mono text-[11px] tabular-nums text-neutral-400">{speed}</span>
      </div>
    </div>
  );
}
