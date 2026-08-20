import { useState } from 'react';
import { CirclePause } from 'lucide-react';
import { SegmentedPill } from './SegmentedPill';

type PauseMode = 'off' | 'keyword' | 'paragraph';

const MODES: { value: PauseMode; label: string }[] = [
  { value: 'off', label: '关闭' },
  { value: 'paragraph', label: '空行' },
  { value: 'keyword', label: '关键词' },
];

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
      className="w-full min-w-0 flex-1 rounded-lg border border-white/5 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 transition-colors focus:border-[#D4A432] focus:outline-none"
    />
  );

  if (inline) {
    return (
      <div className="flex items-center gap-2">
        <CirclePause size={16} className="text-white/30 shrink-0" />
        <span className="text-sm font-semibold text-white shrink-0">自动暂停</span>
        <SegmentedPill className="shrink-0" value={mode} options={MODES} onSelect={handleSelect} />
        {keywordInput}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <span className="flex items-center gap-2">
        <CirclePause size={16} className="text-white/30" />
        <span className="text-sm font-semibold text-white">自动暂停</span>
      </span>
      <SegmentedPill value={mode} options={MODES} onSelect={handleSelect} />
      {keywordInput}
    </div>
  );
}
