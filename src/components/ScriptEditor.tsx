import { useState } from 'react';
import { ChevronLeft, CirclePause } from 'lucide-react';
import { Script } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';

interface Props {
  script: Script;
  pauseKeyword: string;
  onPauseKeywordChange: (kw: string) => void;
  pauseOnParagraph: boolean;
  onPauseOnParagraphChange: (v: boolean) => void;
  onSave: (id: string, title: string, content: string) => void;
  onBack: () => void;
}

export function ScriptEditor({ script, pauseKeyword, onPauseKeywordChange, pauseOnParagraph, onPauseOnParagraphChange, onSave, onBack }: Props) {
  const [title, setTitle] = useState(script.title);
  const [content, setContent] = useState(script.content);
  const [pauseMode, setPauseMode] = useState<'off' | 'keyword' | 'paragraph'>(
    pauseKeyword ? 'keyword' :
    pauseOnParagraph ? 'paragraph' : 'off',
  );

  const debouncedSave = useDebouncedCallback(
    (t: string, c: string) => onSave(script.id, t, c),
    500
  );

  const onTitleChange = (v: string) => {
    setTitle(v);
    debouncedSave(v, content);
  };
  const onContentChange = (v: string) => {
    setContent(v);
    debouncedSave(title, v);
  };

  return (
    <div className="flex min-h-screen flex-col bg-black">
      <header className="sticky top-0 z-50 flex items-center justify-between border-b border-neutral-900 bg-black/70 px-4 pb-4 pt-[calc(1rem+env(safe-area-inset-top))] backdrop-blur-xl">
        <button title="返回" onClick={onBack} className="rounded-full p-2 text-neutral-400 hover:bg-neutral-800 hover:text-white">
          <ChevronLeft size={20} />
        </button>
        <span className="text-[10px] font-mono uppercase tracking-widest text-neutral-500">自动保存</span>
      </header>
      <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-4 p-4">
        <input
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          placeholder="稿件标题"
          className="w-full rounded-xl border border-neutral-800 bg-neutral-900 p-4 text-xl font-bold text-white focus:border-yellow-500/50 focus:outline-none"
        />

        {(() => {
          const MODES: { value: 'off' | 'keyword' | 'paragraph'; label: string }[] = [
            { value: 'off', label: '关闭' },
            { value: 'keyword', label: '关键词' },
            { value: 'paragraph', label: '空行' },
          ];

          const desc: Record<'off' | 'keyword' | 'paragraph', string> = {
            off: '未启用',
            keyword: '滚动到关键词时暂停',
            paragraph: '遇到空行时暂停',
          };

          return (
            <div className="rounded-xl border border-neutral-800 bg-neutral-900 p-4 space-y-3">
              <div className="flex items-center gap-2">
                <CirclePause size={16} className="text-neutral-500" />
                <div>
                  <span className="block text-sm text-white">自动暂停</span>
                  <span className="text-[10px] text-neutral-500">{desc[pauseMode]}</span>
                </div>
              </div>
              <div className="flex gap-2">
                {MODES.map(({ value, label }) => (
                  <button
                    key={value}
                    onClick={() => {
                      setPauseMode(value);
                      if (value === 'off') { onPauseKeywordChange(''); onPauseOnParagraphChange(false); }
                      else if (value === 'keyword') onPauseOnParagraphChange(false);
                      else { onPauseKeywordChange(''); onPauseOnParagraphChange(true); }
                    }}
                    className={`flex-1 rounded-lg py-2 text-sm transition-colors ${
                      pauseMode === value
                        ? 'bg-yellow-500/15 text-yellow-500'
                        : 'bg-neutral-800 text-neutral-400 hover:text-white'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
              {pauseMode === 'keyword' && (
                <input
                  type="text"
                  value={pauseKeyword}
                  onChange={(e) => onPauseKeywordChange(e.target.value)}
                  placeholder="输入关键词"
                  className="w-full rounded-lg border border-neutral-700 bg-neutral-950 px-3 py-2 text-sm text-white placeholder-neutral-600 focus:border-yellow-500/50 focus:outline-none"
                />
              )}
            </div>
          );
        })()}

        <textarea
          value={content}
          onChange={(e) => onContentChange(e.target.value)}
          placeholder="在此输入或粘贴提词稿件..."
          className="min-h-[40dvh] flex-1 resize-none rounded-xl border border-neutral-800 bg-neutral-900 p-6 text-lg leading-relaxed text-neutral-300 focus:border-yellow-500/50 focus:outline-none"
        />
      </main>
    </div>
  );
}
