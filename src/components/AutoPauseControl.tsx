import { useState, useRef, useLayoutEffect } from 'react';
import { CirclePause } from 'lucide-react';

type PauseMode = 'off' | 'keyword' | 'paragraph';

const MODES: { value: PauseMode; label: string }[] = [
  { value: 'off', label: '关闭' },
  { value: 'keyword', label: '关键词' },
  { value: 'paragraph', label: '空行' },
];

const DESC: Record<PauseMode, string> = {
  off: '未启用',
  keyword: '滚动到关键词时暂停',
  paragraph: '遇到空行时暂停',
};

function deriveMode(keyword: string, paragraph: boolean): PauseMode {
  return keyword ? 'keyword' : paragraph ? 'paragraph' : 'off';
}

interface Props {
  keyword: string;
  paragraph: boolean;
  onChange: (patch: { pauseKeyword?: string; pauseOnParagraph?: boolean }) => void;
  inline?: boolean;
}

/** Sliding pill for mode buttons — positions via getBoundingClientRect */
function ModePillGroup({
  mode,
  onSelect,
}: {
  mode: PauseMode;
  onSelect: (v: PauseMode) => void;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const pillRef = useRef<HTMLDivElement | null>(null);

  useLayoutEffect(() => {
    const container = containerRef.current;
    const pill = pillRef.current;
    if (!container || !pill) return;
    const btn = container.querySelector<HTMLButtonElement>(
      `[data-mode-value="${mode}"]`
    );
    if (!btn) return;
    const cr = container.getBoundingClientRect();
    const br = btn.getBoundingClientRect();
    pill.style.left = `${br.left - cr.left}px`;
    pill.style.width = `${br.width}px`;
  }, [mode]);

  return (
    <div
      ref={containerRef}
      className="relative flex items-center rounded-full glass-button py-0.5 px-0.5"
    >
      <div
        ref={pillRef}
        className="absolute top-0.5 rounded-full bg-white/15 transition-all duration-300 ease-out"
        style={{ height: 'calc(100% - 4px)' }}
      />
      {MODES.map(({ value, label }) => (
        <button
          key={value}
          data-mode-value={value}
          onClick={() => onSelect(value)}
          className={`relative z-10 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors ${
            mode === value
              ? 'text-white'
              : 'text-white/35 hover:text-white/60'
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

export function AutoPauseControl({ keyword, paragraph, onChange, inline = false }: Props) {
  const [mode, setMode] = useState<PauseMode>(() => deriveMode(keyword, paragraph));

  const handleSelect = (value: PauseMode) => {
    setMode(value);
    if (value === 'off') onChange({ pauseKeyword: '', pauseOnParagraph: false });
    else if (value === 'keyword') onChange({ pauseOnParagraph: false });
    else onChange({ pauseKeyword: '', pauseOnParagraph: true });
  };

  const keywordInput = mode === 'keyword' && (
    <input
      type="text"
      value={keyword}
      onChange={(e) => onChange({ pauseKeyword: e.target.value })}
      placeholder="输入关键词"
      className="w-full rounded-lg border border-white/5 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 transition-colors focus:border-[#D4A432] focus:outline-none"
    />
  );

  if (inline) {
    return (
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <CirclePause size={16} className="text-white/30 shrink-0" />
          <span className="text-sm font-semibold text-white/50 shrink-0">自动暂停</span>
          <ModePillGroup mode={mode} onSelect={handleSelect} />
        </div>
        {keywordInput}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <CirclePause size={18} className="text-white/30" />
        <div>
          <span className="block text-sm font-semibold text-white">自动暂停</span>
          <span className="text-[11px] text-white/30">{DESC[mode]}</span>
        </div>
      </div>
      <ModePillGroup mode={mode} onSelect={handleSelect} />
      {keywordInput}
    </div>
  );
}
