import { useState } from 'react';
import { ChevronLeft } from 'lucide-react';
import { Script } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';

interface Props {
  script: Script;
  onSave: (id: string, title: string, content: string) => void;
  onBack: () => void;
}

export function ScriptEditor({ script, onSave, onBack }: Props) {
  const [title, setTitle] = useState(script.title);
  const [content, setContent] = useState(script.content);

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
        <textarea
          value={content}
          onChange={(e) => onContentChange(e.target.value)}
          placeholder="在此输入或粘贴提词稿件..."
          className="min-h-[60vh] flex-1 resize-none rounded-xl border border-neutral-800 bg-neutral-900 p-6 text-lg leading-relaxed text-neutral-300 focus:border-yellow-500/50 focus:outline-none"
        />
      </main>
    </div>
  );
}
