import { useRef, useState } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, Play, Download } from 'lucide-react';
import { Script } from '../types';

interface Props {
  scripts: Script[];
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
  onDeleteAll?: () => void;
  onImport?: (title: string, content: string) => void;
}

export function ScriptList({ scripts, onOpen, onEdit, onDelete, onCreate, onDeleteAll, onImport }: Props) {
  const [query, setQuery] = useState('');
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const [importTitle, setImportTitle] = useState('');
  const [importContent, setImportContent] = useState('');
  const fileInputRef = useRef<HTMLInputElement>(null);

  const filtered = scripts.filter(
    (s) =>
      s.title.toLowerCase().includes(query.toLowerCase()) ||
      s.content.toLowerCase().includes(query.toLowerCase())
  );

  const doImport = (title: string, content: string) => {
    if (!content.trim()) return;
    onImport?.(title, content);
    setShowImport(false);
    setImportTitle('');
    setImportContent('');
  };

  const handleFiles = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    for (const f of files) {
      const text = await f.text();
      const title = f.name.replace(/\.[^.]+$/, '');
      onImport?.(title, text);
    }
    setShowImport(false);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  return (
    <div className="flex min-h-screen flex-col bg-[#050505] text-white">
      <header className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))] backdrop-blur-xl" style={{ paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))', paddingRight: 'calc(0.75rem + env(safe-area-inset-right))' }}>
        <div className="mx-auto flex max-w-5xl items-center gap-2">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-yellow-500 text-black sm:h-9 sm:w-9">
            <FileText size={18} />
          </div>
          <h1 className="hidden text-base font-bold sm:block">稿件管理</h1>
          <div className="relative ml-auto">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-neutral-600" size={14} />
            <input
              placeholder="搜索..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-28 rounded-full border border-neutral-800 bg-neutral-900 py-2 pl-8 pr-2.5 text-sm focus:border-yellow-500/50 focus:outline-none sm:w-48"
            />
          </div>
          {onImport && (
            <button
              onClick={() => setShowImport(true)}
              className="flex shrink-0 items-center gap-1 rounded-full border border-neutral-700 px-2.5 py-2 text-xs font-bold text-neutral-300 active:scale-95 sm:gap-1.5 sm:px-3 sm:text-sm"
            >
              <Download size={15} /><span className="hidden sm:inline">导入</span>
            </button>
          )}
          <button
            onClick={onCreate}
            className="flex shrink-0 items-center gap-1 rounded-full bg-yellow-500 px-3 py-2 text-xs font-bold text-black active:scale-95 sm:gap-2 sm:px-4 sm:text-sm"
          >
            <Plus size={16} /><span className="hidden sm:inline">新建</span><span className="sm:hidden">稿</span>
          </button>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 py-8" style={{ paddingLeft: 'calc(1rem + env(safe-area-inset-left))', paddingRight: 'calc(1rem + env(safe-area-inset-right))' }}>
        {scripts.length > 0 && onDeleteAll && (
          <div className="mx-auto mb-4 flex max-w-5xl items-center justify-end gap-3 text-xs text-neutral-600">
            <span>共 {scripts.length} 篇</span>
            <button
              onClick={() => setConfirmClear(true)}
              className="flex items-center gap-1 text-neutral-500 transition-colors hover:text-red-400"
            >
              <Trash2 size={13} /> 清空全部
            </button>
          </div>
        )}

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 text-center">
            <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-3xl bg-neutral-900 text-neutral-700">
              <FileText size={32} />
            </div>
            <p className="text-neutral-500">还没有稿件，点击右上角「新建稿件」去新建第一篇提词脚本吧</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {filtered.map((s) => (
              <div
                key={s.id}
                onClick={() => onOpen(s.id)}
                className="group relative cursor-pointer overflow-hidden rounded-2xl border border-neutral-800/60 bg-neutral-900/40 p-5 transition-all hover:border-yellow-500/30 hover:bg-neutral-900"
              >
                <div className="mb-3 flex items-start justify-between">
                  <div className="rounded-lg bg-neutral-800 p-2 text-neutral-400 group-hover:text-yellow-500">
                    <FileText size={18} />
                  </div>
                  <div className="flex gap-1">
                    <button
                      onClick={(e) => { e.stopPropagation(); onEdit(s.id); }}
                      className="rounded-lg p-2 text-neutral-400 hover:bg-neutral-800 hover:text-white"
                    >
                      <Edit3 size={16} />
                    </button>
                    <button
                      data-testid={`delete-${s.id}`}
                      onClick={(e) => { e.stopPropagation(); setConfirmId(s.id); }}
                      className="rounded-lg p-2 text-neutral-400 hover:bg-red-500/10 hover:text-red-400"
                    >
                      <Trash2 size={16} />
                    </button>
                  </div>
                </div>
                <h3 className="mb-1 truncate text-lg font-semibold">{s.title}</h3>
                <p className="mb-3 line-clamp-2 text-sm text-neutral-500">
                  {s.content || <span className="italic text-neutral-700">无内容...</span>}
                </p>
                <div className="flex items-center gap-2 border-t border-neutral-800/50 pt-3 text-[10px] text-neutral-600">
                  {new Date(s.updatedAt).toLocaleDateString()}
                  <span className="ml-auto flex items-center gap-1 text-yellow-500">
                    开始提词 <Play size={12} fill="currentColor" />
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* 导入面板 */}
      {showImport && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/80" onClick={() => setShowImport(false)} />
          <div className="relative flex max-h-[85vh] w-full max-w-lg flex-col overflow-hidden rounded-3xl border border-neutral-800 bg-neutral-900">
            <div className="border-b border-neutral-800 p-6 pb-4">
              <h3 className="flex items-center gap-2 text-xl font-bold"><Download size={20} /> 导入稿件</h3>
              <p className="mt-1 text-xs leading-relaxed text-neutral-500">
                从苹果备忘录导入：在备忘录中全选复制，粘贴到下方；或用备忘录「发送副本 → 存储到文件」导出 .txt 后选择文件（支持多选）。
              </p>
            </div>
            <div className="flex flex-1 flex-col gap-3 overflow-y-auto p-6">
              <input
                value={importTitle}
                onChange={(e) => setImportTitle(e.target.value)}
                placeholder="稿件标题（可选，留空则用导入的内容首句或文件名）"
                className="w-full rounded-xl border border-neutral-800 bg-neutral-950 p-3 text-sm focus:border-yellow-500/50 focus:outline-none"
              />
              <textarea
                value={importContent}
                onChange={(e) => setImportContent(e.target.value)}
                placeholder="在此粘贴稿件内容..."
                className="min-h-[30dvh] flex-1 resize-none rounded-xl border border-neutral-800 bg-neutral-950 p-4 text-base leading-relaxed focus:border-yellow-500/50 focus:outline-none"
              />
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center justify-center gap-2 rounded-xl border border-dashed border-neutral-700 py-3 text-sm text-neutral-400 transition-colors hover:border-yellow-500/50 hover:text-white"
              >
                <Download size={16} /> 选择 .txt / .md 文件
              </button>
              <input ref={fileInputRef} type="file" accept=".txt,.md,text/plain,text/markdown" multiple hidden onChange={handleFiles} />
            </div>
            <div className="flex gap-3 border-t border-neutral-800 p-4">
              <button onClick={() => setShowImport(false)} className="flex-1 rounded-xl bg-neutral-800 py-3 text-sm font-bold">取消</button>
              <button
                onClick={() => doImport(importTitle, importContent)}
                disabled={!importContent.trim()}
                className="flex-1 rounded-xl bg-yellow-500 py-3 text-sm font-bold text-black disabled:opacity-40"
              >导入确认</button>
            </div>
          </div>
        </div>
      )}

      {/* 清空全部确认 */}
      {confirmClear && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/80" onClick={() => setConfirmClear(false)} />
          <div className="relative w-full max-w-sm rounded-3xl border border-neutral-800 bg-neutral-900 p-8">
            <h3 className="mb-2 text-xl font-bold">确认清空全部稿件？</h3>
            <p className="mb-6 text-sm text-neutral-400">将删除全部 {scripts.length} 篇稿件，此操作不可撤销。</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmClear(false)} className="flex-1 rounded-xl bg-neutral-800 py-3 text-sm font-bold">取消</button>
              <button
                onClick={() => { onDeleteAll?.(); setConfirmClear(false); }}
                className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold"
              >确认清空</button>
            </div>
          </div>
        </div>
      )}

      {/* 删除单个确认 */}
      {confirmId && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/80" onClick={() => setConfirmId(null)} />
          <div className="relative w-full max-w-sm rounded-3xl border border-neutral-800 bg-neutral-900 p-8">
            <h3 className="mb-2 text-xl font-bold">确认删除稿件？</h3>
            <p className="mb-6 text-sm text-neutral-400">此操作不可撤销。</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmId(null)} className="flex-1 rounded-xl bg-neutral-800 py-3 text-sm font-bold">取消</button>
              <button
                onClick={() => { onDelete(confirmId); setConfirmId(null); }}
                className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold"
              >确认删除</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
