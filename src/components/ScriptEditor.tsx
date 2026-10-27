import { useState } from 'react';
import { ChevronLeft, Folder, Plus, Scissors } from 'lucide-react';
import { Script, SplitMode } from '../types';
import { useDebouncedCallback } from '../hooks/useDebouncedCallback';
import { AutoPauseControl } from './AutoPauseControl';
import { SegmentedPill } from './SegmentedPill';
import { FilterChip } from './ScriptList';

const SPLIT_OPTIONS: { value: SplitMode; label: string }[] = [
  { value: 'paragraph', label: '空行' },
  { value: 'keyword', label: '关键词' },
];

interface Props {
  script: Script;
  /** 当前稿件所在文件夹（undefined = 未分组） */
  folder?: string;
  /** 全部文件夹（App 从稿件派生传入） */
  folders: string[];
  /** 选择/新建分组；null = 移出到未分组 */
  onFolderChange: (folder: string | null) => void;
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
  folder,
  folders,
  onFolderChange,
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
  // 分组行内联新建输入框
  const [newFolderOpen, setNewFolderOpen] = useState(false);
  const [newFolderName, setNewFolderName] = useState('');

  const commitNewFolder = () => {
    const name = newFolderName.trim();
    setNewFolderOpen(false);
    if (name) onFolderChange(name); // 新文件夹随本稿件落地，派生模型立即成立
  };

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
      <main className="mx-auto flex w-full max-w-[45rem] flex-1 flex-col px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-[calc(1rem+env(safe-area-inset-bottom))]">
        {/* Title Row: Back + Title Input */}
        <div className="flex items-center gap-1">
          <button
            title="返回"
            onClick={handleBack}
            aria-label="返回"
            className="-ml-3 flex shrink-0 items-center justify-center rounded-full p-2 glass-button text-white/50 hover:text-white active:scale-95"
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

        {/* Toolbar: Folder 分组（新建稿件时决定归入哪个文件夹） */}
        <div className="flex items-center gap-2 border-b border-white/5 py-2.5">
          <Folder size={16} className="shrink-0 text-white/30" />
          <span className="shrink-0 text-sm font-semibold text-white">分组</span>
          <div className="flex min-w-0 flex-1 items-center gap-1.5 overflow-x-auto py-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <FilterChip active={!folder} onClick={() => onFolderChange(null)}>未分组</FilterChip>
            {folders.map((f) => (
              <FilterChip key={f} active={folder === f} onClick={() => onFolderChange(f)}>{f}</FilterChip>
            ))}
            {newFolderOpen ? (
              <input
                autoFocus
                value={newFolderName}
                onChange={(e) => setNewFolderName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.nativeEvent.isComposing) return; // 中文输入法选字回车不当作提交（此时值尚未合成）
                  if (e.key === 'Enter') commitNewFolder();
                  if (e.key === 'Escape') setNewFolderOpen(false);
                }}
                onBlur={commitNewFolder}
                placeholder="新分组名"
                aria-label="新分组名"
                className="w-28 shrink-0 rounded-full border border-[#D4A432]/40 bg-white/5 px-3 py-1 text-xs text-white placeholder-white/30 focus:outline-none"
              />
            ) : (
              <button
                onClick={() => { setNewFolderName(''); setNewFolderOpen(true); }}
                aria-label="新建分组"
                className="flex shrink-0 items-center gap-0.5 rounded-full chip-glass px-2.5 py-1 text-xs font-medium text-white/40 transition-colors hover:text-white/80"
              >
                <Plus size={11} />新建
              </button>
            )}
          </div>
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
