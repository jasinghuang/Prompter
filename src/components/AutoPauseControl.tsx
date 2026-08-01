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
  /** ScriptEditor 内联模式：去掉卡片壳和图标标题，仅保留分段按钮 */
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
          className={`rounded-lg px-3 py-1.5 text-xs transition-colors ${
            mode === value
              ? 'bg-yellow-500/15 text-yellow-500'
              : 'text-neutral-500 hover:text-neutral-300'
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
      className="w-full rounded-lg border border-neutral-800 bg-neutral-900 px-3 py-1.5 text-sm text-white placeholder-neutral-600 focus:border-yellow-500/50 focus:outline-none"
    />
  );

  if (inline) {
    return (
      <div className="space-y-2">
        <div className="flex items-center gap-2">
          <CirclePause size={14} className="text-neutral-500 shrink-0" />
          <span className="text-xs font-semibold text-neutral-400 shrink-0">自动暂停</span>
          {buttons}
        </div>
        {keywordInput}
      </div>
    );
  }

  return (
    <div className="rounded-xl bg-neutral-800 p-4 space-y-3">
      <div className="flex items-center gap-3">
        <CirclePause size={18} className="text-neutral-400" />
        <div>
          <span className="block text-sm text-white">自动暂停</span>
          <span className="text-[10px] text-neutral-500">{DESC[mode]}</span>
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
            className={`flex-1 rounded-lg py-2 text-sm transition-colors ${
              mode === value
                ? 'bg-yellow-500/15 text-yellow-500'
                : 'bg-neutral-700 text-neutral-400 hover:text-white'
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
