import { useState } from 'react';
import { ChevronLeft, Scissors } from 'lucide-react';
import { Script, SplitMode } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';
import { AutoPauseControl } from './AutoPauseControl';
import { SegmentedPill } from './SegmentedPill';

const SPLIT_OPTIONS: { value: SplitMode; label: string }[] = [
  { value: 'paragraph', label: '空行' },
  { value: 'keyword', label: '关键词' },
];

interface Props {
  script: Script;
  pauseKeyword: string;
  onPauseKeywordChange: (kw: string) => void;
  pauseOnParagraph: boolean;
  onPauseOnParagraphChange: (v: boolean) => void;
  splitMode: SplitMode;
  onSplitModeChange: (m: SplitMode) => void;
  splitKeyword: string;
  onSplitKeywordChange: (kw: string) => void;
  onSave: (id: string, title: string, content: string) => void;
  onBack: () => void;
  /** 以编辑器当前内容拆分（不等待防抖落库） */
  onSplit: (content: string) => void;
}

export function ScriptEditor({
  script,
  pauseKeyword,
  onPauseKeywordChange,
  pauseOnParagraph,
  onPauseOnParagraphChange,
  splitMode,
  onSplitModeChange,
  splitKeyword,
  onSplitKeywordChange,
  onSave,
  onBack,
  onSplit,
}: Props) {
  const [title, setTitle] = useState(script.title);
  const [content, setContent] = useState(script.content);

  const debouncedSave = useDebouncedCallback((t: string, c: string) => onSave(script.id, t, c), 500);

  const onTitleChange = (v: string) => {
    setTitle(v);
    debouncedSave(v, content);
  };
  const onContentChange = (v: string) => {
    setContent(v);
    debouncedSave(title, v);
  };

  const handleBack = () => {
    onSave(script.id, title, content);
    onBack();
  };

  const splitDisabled =
    splitMode === 'keyword'
      ? !splitKeyword || !content.includes(splitKeyword)
      : !content.includes('\n\n');

  return (
    <div className="flex min-h-screen flex-col bg-[#0A0A0B]">
      <main className="mx-auto flex w-full max-w-[45rem] flex-1 flex-col px-4 pt-[calc(1rem+env(safe-area-inset-top))]">
        {/* Title Row: Back + Title Input */}
        <div className="flex items-center gap-1">
          <button
            title="返回"
            onClick={handleBack}
            className="-ml-3 flex shrink-0 items-center justify-center rounded-full p-2 text-white/30 hover:bg-white/10 hover:text-white"
            style={{ minHeight: '44px', minWidth: '44px' }}
          >
            <ChevronLeft size={20} />
          </button>
          <input
            value={title}
            onChange={(e) => onTitleChange(e.target.value)}
            placeholder="稿件标题"
            className="min-w-0 flex-1 border-b border-white/5 bg-transparent py-3 text-lg font-semibold text-white placeholder-white/30 transition-colors focus:border-[#D4A432] focus:outline-none"
          />
        </div>

        {/* Toolbar: Smart Split — mode pill + keyword input + action */}
        <div className="border-b border-white/5 py-2.5">
          <div className="flex items-center gap-2">
            <SegmentedPill
              value={splitMode}
              options={SPLIT_OPTIONS}
              onSelect={onSplitModeChange}
              className="shrink-0"
            />
            {splitMode === 'keyword' && (
              <input
                type="text"
                value={splitKeyword}
                onChange={(e) => onSplitKeywordChange(e.target.value)}
                placeholder="输入拆分关键词"
                className="w-full min-w-0 flex-1 rounded-lg border border-white/5 bg-white/5 px-3 py-2 text-sm text-white placeholder-white/30 transition-colors focus:border-[#D4A432] focus:outline-none"
              />
            )}
            <button
              onClick={() => onSplit(content)}
              disabled={splitDisabled}
              className="flex shrink-0 items-center gap-1.5 rounded-full bg-[#D4A432] px-3.5 py-1.5 text-sm font-bold text-[#0A0A0B] transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-30"
            >
              <Scissors size={12} />
              智能拆分
            </button>
          </div>
        </div>

        {/* Toolbar: AutoPause */}
        <div className="border-b border-white/5 py-2.5">
          <AutoPauseControl
            inline
            keyword={pauseKeyword}
            paragraph={pauseOnParagraph}
            onChange={(patch) => {
              if (patch.pauseKeyword !== undefined) onPauseKeywordChange(patch.pauseKeyword);
              if (patch.pauseOnParagraph !== undefined) onPauseOnParagraphChange(patch.pauseOnParagraph);
            }}
          />
        </div>

        {/* Content Textarea */}
        <textarea
          value={content}
          onChange={(e) => onContentChange(e.target.value)}
          placeholder="在此输入或粘贴提词稿件..."
          className="flex-1 resize-none bg-transparent py-4 text-lg leading-relaxed text-white placeholder-white/30 focus:outline-none"
        />
      </main>
    </div>
  );
}
