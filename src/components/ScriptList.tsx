import { useState } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, Play } from 'lucide-react';
import { Script } from '../types';

interface Props {
  scripts: Script[];
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
}

export function ScriptList({ scripts, onOpen, onEdit, onDelete, onCreate }: Props) {
  const [query, setQuery] = useState('');
  const [confirmId, setConfirmId] = useState<string | null>(null);

  const filtered = scripts.filter(
    (s) =>
      s.title.toLowerCase().includes(query.toLowerCase()) ||
      s.content.toLowerCase().includes(query.toLowerCase())
  );

  return (
    <div className="flex min-h-screen flex-col bg-[#050505] text-white">
      <header className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 px-4 py-3 backdrop-blur-xl">
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-yellow-500 text-black">
            <FileText size={20} />
          </div>
          <h1 className="text-base font-bold">稿件管理</h1>
          <div className="relative ml-auto">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-neutral-600" size={16} />
            <input
              placeholder="搜索稿件..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-40 rounded-full border border-neutral-800 bg-neutral-900 py-2 pl-9 pr-3 text-sm focus:border-yellow-500/50 focus:outline-none sm:w-64"
            />
          </div>
          <button
            onClick={onCreate}
            className="flex items-center gap-2 rounded-full bg-yellow-500 px-4 py-2 text-sm font-bold text-black active:scale-95"
          >
            <Plus size={18} /> 新建稿件
          </button>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-8">
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
                  <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
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
                  <span className="ml-auto flex items-center gap-1 text-yellow-500 opacity-0 group-hover:opacity-100">
                    开始提词 <Play size={12} fill="currentColor" />
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* 删除确认 */}
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
