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
  /** 当前设置中的关键词（可空） */
  keyword: string;
  /** 当前设置中的段落暂停开关 */
  paragraph: boolean;
  /** 模式或关键词变更时回调 */
  onChange: (patch: { pauseKeyword?: string; pauseOnParagraph?: boolean }) => void;
  /** 紧凑模式（ScriptEditor 使用），缩小图标尺寸 */
  compact?: boolean;
}

export function AutoPauseControl({ keyword, paragraph, onChange, compact = false }: Props) {
  const [mode, setMode] = useState<PauseMode>(() => deriveMode(keyword, paragraph));

  const iconSize = compact ? 16 : 18;

  return (
    <div className="rounded-xl bg-neutral-800 p-4 space-y-3">
      <div className={`flex items-center ${compact ? 'gap-2' : 'gap-3'}`}>
        <CirclePause size={iconSize} className={compact ? 'text-neutral-500' : 'text-neutral-400'} />
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
                : compact
                  ? 'bg-neutral-800 text-neutral-400 hover:text-white'
                  : 'bg-neutral-700 text-neutral-400 hover:text-white'
            }`}
          >
            {label}
          </button>
        ))}
      </div>
      {mode === 'keyword' && (
        <input
          type="text"
          value={keyword}
          onChange={(e) => onChange({ pauseKeyword: e.target.value })}
          placeholder="输入关键词"
          className={`w-full rounded-lg border border-neutral-700 px-3 py-2 text-sm text-white placeholder-neutral-600 focus:border-yellow-500/50 focus:outline-none ${compact ? 'bg-neutral-950' : 'bg-neutral-900'}`}
        />
      )}
    </div>
  );
}
