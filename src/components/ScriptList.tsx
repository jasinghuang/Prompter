import { useMemo, useState } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, Play, ArrowUpDown } from 'lucide-react';
import { Script } from '../types';
import { countReadableChars } from '../lib/tokens';

interface Props {
  scripts: Script[];
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
  onDeleteAll?: () => void;
}

type SortKey = 'date' | 'title' | 'chars';

const SORT_OPTIONS: { value: SortKey; label: string }[] = [
  { value: 'date', label: '日期' },
  { value: 'title', label: '标题' },
  { value: 'chars', label: '字数' },
];

export function ScriptList({ scripts, onOpen, onEdit, onDelete, onCreate, onDeleteAll }: Props) {
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<SortKey>('date');
  const [asc, setAsc] = useState(false);
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);

  const charCounts = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of scripts) map.set(s.id, countReadableChars(s.content));
    return map;
  }, [scripts]);

  const sorted = useMemo(() => {
    const list = [...scripts];
    const dir = asc ? 1 : -1;
    if (sort === 'title') list.sort((a, b) => dir * a.title.localeCompare(b.title, 'zh'));
    else if (sort === 'chars') list.sort((a, b) => dir * ((charCounts.get(a.id) ?? 0) - (charCounts.get(b.id) ?? 0)));
    else list.sort((a, b) => dir * (b.createdAt - a.createdAt));
    return list;
  }, [scripts, sort, asc, charCounts]);

  const filtered = sorted.filter(
    (s) =>
      s.title.toLowerCase().includes(query.toLowerCase()) ||
      s.content.toLowerCase().includes(query.toLowerCase())
  );

  return (
    <div className="flex min-h-screen flex-col bg-[#050505] text-white">
      <header className="sticky top-0 z-50 border-b border-neutral-900 bg-black/60 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))] backdrop-blur-xl" style={{ paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))', paddingRight: 'calc(0.75rem + env(safe-area-inset-right))' }}>
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          <div className="flex items-center gap-2">
            <img src="./icon.svg" alt="" className="h-7 w-7 rounded-lg" />
            <h1 className="text-base font-bold">提词器</h1>
          </div>
          <div className="relative ml-auto">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-neutral-600" size={14} />
            <input
              placeholder="搜索..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-28 rounded-full border border-neutral-800 bg-neutral-900 py-2 pl-8 pr-2.5 text-sm focus:border-yellow-500/50 focus:outline-none sm:w-48"
            />
          </div>
          <button
            onClick={onCreate}
            className="flex shrink-0 items-center gap-1 rounded-full bg-yellow-500 px-3 py-2 text-xs font-bold text-black active:scale-95 sm:gap-2 sm:px-4 sm:text-sm"
          >
            <Plus size={16} />新建稿件
          </button>
        </div>
      </header>

      <main className="mx-auto w-full max-w-5xl flex-1 py-8" style={{ paddingLeft: 'calc(1rem + env(safe-area-inset-left))', paddingRight: 'calc(1rem + env(safe-area-inset-right))' }}>
        {scripts.length > 0 && onDeleteAll && (
          <div className="mb-4 flex items-center gap-3 text-xs text-neutral-600">
            <span>共 {scripts.length} 篇</span>
            <div className="flex items-center gap-1">
              <ArrowUpDown size={11} className="text-neutral-600" />
              {SORT_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    if (sort === opt.value) setAsc((v) => !v);
                    else { setSort(opt.value); setAsc(false); }
                  }}
                  className={sort === opt.value ? 'text-yellow-500' : 'text-neutral-500 hover:text-neutral-300 transition-colors'}
                >
                  {opt.label}{sort === opt.value ? (asc ? ' ↑' : ' ↓') : ''}
                </button>
              ))}
            </div>
            <button
              onClick={() => setConfirmClear(true)}
              className="ml-auto flex items-center gap-1 text-neutral-500 transition-colors hover:text-red-400"
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
            {scripts.length === 0 ? (
              <p className="text-neutral-500">还没有稿件，点击右上角「新建稿件」去新建第一篇提词脚本吧</p>
            ) : (
              <p className="text-neutral-500">未找到与「{query}」匹配的稿件</p>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {filtered.map((s) => (
              <div
                key={s.id}
                onClick={() => onOpen(s.id)}
                className="group relative cursor-pointer rounded-2xl border border-yellow-500/20 bg-neutral-900/40 p-4 shadow-[0_0_6px_rgba(234,179,8,0.12)] transition-all hover:border-yellow-500/40 hover:bg-neutral-900 hover:shadow-[0_0_8px_rgba(234,179,8,0.2)]"
              >
                <div className="mb-2 flex items-start justify-between">
                  <h3 className="truncate text-base font-semibold">{s.title}</h3>
                  <div className="flex shrink-0 gap-0.5 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={(e) => { e.stopPropagation(); onEdit(s.id); }}
                      className="rounded-lg p-1.5 text-neutral-400 hover:bg-neutral-800 hover:text-white"
                    >
                      <Edit3 size={14} />
                    </button>
                    <button
                      data-testid={`delete-${s.id}`}
                      onClick={(e) => { e.stopPropagation(); setConfirmId(s.id); }}
                      className="rounded-lg p-1.5 text-neutral-400 hover:bg-red-500/10 hover:text-red-400"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
                {s.content && (
                  <p className="mb-3 line-clamp-2 text-sm leading-relaxed text-neutral-500">{s.content}</p>
                )}
                <div className="flex items-center gap-2 text-[10px] text-neutral-600">
                  {new Date(s.updatedAt).toLocaleDateString()}
                  <span>|</span>
                  <span>{charCounts.get(s.id)}字</span>
                  <button
                    onClick={(e) => { e.stopPropagation(); onOpen(s.id); }}
                    className="ml-auto flex items-center gap-1 rounded-full bg-yellow-500 px-3 py-1.5 text-xs font-bold text-black active:scale-95 transition-transform"
                  >
                    开始提词 <Play size={11} fill="currentColor" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

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
