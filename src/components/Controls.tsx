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
    <div className={`absolute bottom-[calc(0.75rem+env(safe-area-inset-bottom))] left-3 right-3 z-50 flex items-center gap-3 rounded-2xl border border-yellow-500/20 bg-black/30 px-4 py-2.5 shadow-[0_0_6px_rgba(234,179,8,0.12)] backdrop-blur-xl transition-all duration-300 ${
      visible ? 'translate-y-0 opacity-100' : 'translate-y-20 opacity-0 pointer-events-none'
    }`}>
      <Type size={13} className="shrink-0 text-neutral-300" />
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
      <span className="w-6 shrink-0 text-right font-mono text-[11px] tabular-nums text-neutral-300">{fontSize}</span>
      <Gauge size={13} className="shrink-0 text-neutral-300" />
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
      <span className="w-7 shrink-0 text-right font-mono text-[11px] tabular-nums text-neutral-300">{speed}</span>
    </div>
  );
}
