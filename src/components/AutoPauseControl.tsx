import { useState } from 'react';
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

export function AutoPauseControl({ keyword, paragraph, onChange, inline = false }: Props) {
  const [mode, setMode] = useState<PauseMode>(() => deriveMode(keyword, paragraph));

  const buttons = (
    <div className="flex gap-1.5">
      {MODES.map(({ value, label }) => (
        <button
          key={value}
          onClick={() => {
            setMode(value);
            if (value === 'off') onChange({ pauseKeyword: '', pauseOnParagraph: false });
            else if (value === 'keyword') onChange({ pauseOnParagraph: false });
            else onChange({ pauseKeyword: '', pauseOnParagraph: true });
          }}
          className={`rounded-lg px-3 py-1.5 text-xs font-medium ${
            mode === value
              ? 'bg-[rgba(212,164,50,0.15)] text-[#D4A432]'
              : 'text-[#71717A] hover:text-[#A1A1AA] hover:bg-[rgba(212,164,50,0.06)]'
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  );

  const keywordInput = mode === 'keyword' && (
    <input
      type="text"
      value={keyword}
      onChange={(e) => onChange({ pauseKeyword: e.target.value })}
      placeholder="输入关键词"
      className="w-full rounded-lg border border-[#26262B] bg-[#1A1A1F] px-3 py-2 text-sm text-[#F5F5F5] placeholder-[#71717A] transition-colors focus:border-[#D4A432] focus:outline-none focus:ring-2 focus:ring-[rgba(212,164,50,0.15)]"
    />
  );

  // Inline variant for ScriptEditor toolbar
  if (inline) {
    return (
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <CirclePause size={14} className="text-[#71717A] shrink-0" />
          <span className="text-xs font-semibold text-[#A1A1AA] shrink-0">自动暂停</span>
          {buttons}
        </div>
        {keywordInput}
      </div>
    );
  }

  // Full variant for Settings panel
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <CirclePause size={18} className="text-[#71717A]" />
        <div>
          <span className="block text-sm font-semibold text-[#F5F5F5]">自动暂停</span>
          <span className="text-[11px] text-[#71717A]">{DESC[mode]}</span>
        </div>
      </div>
      <div className="flex gap-2">
        {MODES.map(({ value, label }) => (
          <button
            key={value}
            onClick={() => {
              setMode(value);
              if (value === 'off') onChange({ pauseKeyword: '', pauseOnParagraph: false });
              else if (value === 'keyword') onChange({ pauseOnParagraph: false });
              else onChange({ pauseKeyword: '', pauseOnParagraph: true });
            }}
            className={`flex-1 rounded-lg py-2 text-sm font-medium ${
              mode === value
                ? 'bg-[rgba(212,164,50,0.15)] text-[#D4A432]'
                : 'bg-[#1A1A1F] text-[#A1A1AA] hover:text-[#F5F5F5] hover:bg-[#26262B]'
            }`}
          >
            {label}
          </button>
        ))}
      </div>
      {keywordInput}
    </div>
  );
}
