import { useState } from 'react';
import { ChevronLeft, Scissors } from 'lucide-react';
import { Script } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';
import { AutoPauseControl } from './AutoPauseControl';

interface Props {
  script: Script;
  pauseKeyword: string;
  onPauseKeywordChange: (kw: string) => void;
  pauseOnParagraph: boolean;
  onPauseOnParagraphChange: (v: boolean) => void;
  onSave: (id: string, title: string, content: string) => void;
  onBack: () => void;
  onSplit: () => void;
}

export function ScriptEditor({
  script,
  pauseKeyword,
  onPauseKeywordChange,
  pauseOnParagraph,
  onPauseOnParagraphChange,
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

  return (
    <div className="flex min-h-screen flex-col bg-[#0A0A0B]">
      {/* Header */}
      <header className="sticky top-0 z-50 px-4 pb-3 pt-[calc(1rem+env(safe-area-inset-top))]">
        <button
          title="返回"
          onClick={handleBack}
          className="rounded-full p-2 text-[#71717A] hover:bg-[rgba(212,164,50,0.08)] hover:text-[#F5F5F5]"
          style={{ minHeight: '44px', minWidth: '44px' }}
        >
          <ChevronLeft size={20} />
        </button>
      </header>

      <main className="mx-auto flex w-full max-w-[45rem] flex-1 flex-col px-4">
        {/* Title Input */}
        <input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          placeholder="稿件标题"
          className="w-full border-b border-[#26262B] bg-transparent py-3 text-lg font-semibold text-[#F5F5F5] placeholder-[#71717A] transition-colors focus:border-[#D4A432] focus:outline-none"
        />

        {/* Toolbar: AutoPause + Smart Split */}
        <div className="flex items-start justify-between gap-3 border-b border-[#26262B] py-2.5">
          <AutoPauseControl
            inline
            keyword={pauseKeyword}
            paragraph={pauseOnParagraph}
            onChange={(patch) => {
              if (patch.pauseKeyword !== undefined) onPauseKeywordChange(patch.pauseKeyword);
              if (patch.pauseOnParagraph !== undefined) onPauseOnParagraphChange(patch.pauseOnParagraph);
            }}
          />
          <button
            onClick={onSplit}
            disabled={!script.content.includes('\n\n')}
            className="flex shrink-0 items-center gap-1.5 rounded-full bg-[#D4A432] px-3.5 py-2 text-xs font-bold text-[#0A0A0B] active:scale-[0.97] active:translate-y-px disabled:cursor-not-allowed disabled:opacity-30"
            style={{ minHeight: '44px' }}
          >
            <Scissors size={12} />
            智能拆分
          </button>
        </div>

        {/* Content Textarea */}
        <textarea
          value={content}
          onChange={(e) => onContentChange(e.target.value)}
          placeholder="在此输入或粘贴提词稿件..."
          className="flex-1 resize-none bg-transparent py-4 text-lg leading-relaxed text-[#A1A1AA] placeholder-[#71717A] focus:outline-none"
        />
      </main>
    </div>
  );
}
