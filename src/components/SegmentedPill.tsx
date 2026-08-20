import { useEffect, useRef, useState } from 'react';

export interface SegmentedPillOption<T extends string> {
  value: T;
  label: string;
}

interface Props<T extends string> {
  value: T;
  options: SegmentedPillOption<T>[];
  onSelect: (value: T) => void;
  className?: string;
}

/**
 * 药丸分段选择器：白色药丸在选项间滑动，选中项白色文字、未选中弱化。
 * （CF10，从 AutoPauseControl 的 ModePillGroup 抽出，供读完动作等复用）
 */
export function SegmentedPill<T extends string>({ value, options, onSelect, className }: Props<T>) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const [pillRect, setPillRect] = useState<{ left: number; width: number }>({ left: 0, width: 0 });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const btn = container.querySelector<HTMLButtonElement>(`[data-pill-value="${value}"]`);
    if (!btn) return;
    const cr = container.getBoundingClientRect();
    const br = btn.getBoundingClientRect();
    setPillRect({ left: br.left - cr.left, width: br.width });
  }, [value, options]);

  return (
    <div
      ref={containerRef}
      data-segmented-pill
      className={`relative flex items-center rounded-full glass-button py-0.5 pl-0.5 pr-0 ${className ?? ''}`}
    >
      <div
        className="absolute top-0.5 rounded-full bg-white/15 transition-all duration-300 ease-out"
        style={{
          height: 'calc(100% - 4px)',
          left: `${pillRect.left}px`,
          width: `${pillRect.width}px`,
        }}
      />
      {options.map(({ value: v, label }) => (
        <button
          key={v}
          data-pill-value={v}
          onClick={() => onSelect(v)}
          className={`relative z-10 flex-1 text-center whitespace-nowrap rounded-full px-2.5 py-1.5 text-xs font-medium transition-colors ${
            value === v ? 'text-white' : 'text-white/35 hover:text-white/60'
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  );
}
