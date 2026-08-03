import { useMemo, useState, useRef, useCallback } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, ArrowUpDown, Check, Clock } from 'lucide-react';
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

const RECENT_KEY = 'prompter_recent';
function loadRecent(): string[] {
  try { return JSON.parse(localStorage.getItem(RECENT_KEY) || '[]'); } catch { return []; }
}
function saveRecent(id: string) {
  const prev = loadRecent().filter((x) => x !== id);
  prev.unshift(id);
  try { localStorage.setItem(RECENT_KEY, JSON.stringify(prev.slice(0, 3))); } catch { /* noop */ }
}

export function ScriptList({ scripts, onOpen, onEdit, onDelete, onCreate, onDeleteAll }: Props) {
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<SortKey>('date');
  const [asc, setAsc] = useState(false);
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const [searchFocused, setSearchFocused] = useState(false);
  const [filmedIds, setFilmedIds] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(localStorage.getItem('prompter_filmed') || '[]')); } catch { return new Set(); }
  });
  const searchRef = useRef<HTMLInputElement>(null);

  const toggleFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      try { localStorage.setItem('prompter_filmed', JSON.stringify([...next])); } catch { /* noop */ }
      return next;
    });
  }, []);

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

  const recentScripts = useMemo(() => {
    if (!searchFocused || query) return [];
    const ids = loadRecent();
    return ids.map((id) => scripts.find((s) => s.id === id)).filter(Boolean) as Script[];
  }, [searchFocused, query, scripts]);

  const handleOpen = useCallback((id: string) => {
    saveRecent(id);
    onOpen(id);
  }, [onOpen]);

  return (
    <div className="flex min-h-screen flex-col bg-[#0A0A0B] text-white">
      {/* Header — glass */}
      <header
        className="sticky top-0 z-50 glass-bar border-b border-white/5"
        style={{
          paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))',
          paddingRight: 'calc(0.75rem + env(safe-area-inset-right))',
          paddingTop: 'calc(0.75rem + env(safe-area-inset-top))',
          paddingBottom: '0.75rem',
        }}
      >
        <div className="mx-auto flex max-w-5xl items-center gap-3">
          <div className="flex items-center gap-2">
            <img src="/icon.svg" alt="" className="h-7 w-7 rounded-lg" />
            <h1 className="text-base font-bold text-white">提词器</h1>
          </div>
          <div className="relative ml-auto">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-white/40" size={14} />
            <input
              ref={searchRef}
              placeholder="搜索稿件..."
              value={query}
              onFocus={() => setSearchFocused(true)}
              onBlur={() => setTimeout(() => setSearchFocused(false), 150)}
              onChange={(e) => setQuery(e.target.value)}
              className="w-28 rounded-full border border-white/10 bg-white/5 py-2 pl-8 pr-2.5 text-sm text-white placeholder-white/30 transition-all focus:w-48 focus:border-[#D4A432]/40 focus:bg-white/10 focus:outline-none sm:w-48"
            />
            {/* Recent quick-access */}
            {searchFocused && !query && recentScripts.length > 0 && (
              <div className="absolute right-0 top-full mt-2 w-56 rounded-xl border border-white/10 glass-surface py-1.5 shadow-xl">
                <div className="px-3 pb-1.5 pt-0.5 text-[10px] text-white/30">最近使用</div>
                {recentScripts.map((s) => (
                  <button
                    key={s.id}
                    onMouseDown={(e) => { e.preventDefault(); handleOpen(s.id); }}
                    className="flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm text-white/70 transition-colors hover:bg-white/10 hover:text-white"
                  >
                    <Clock size={12} className="shrink-0 text-white/30" />
                    <span className="truncate">{s.title}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
          <button
            onClick={onCreate}
            className="flex shrink-0 items-center gap-1.5 rounded-full bg-[#D4A432] px-4 py-2.5 text-xs font-bold text-[#0A0A0B] transition-all active:scale-95 sm:gap-2 sm:text-sm"
            style={{ minHeight: '44px' }}
          >
            <Plus size={16} />新建稿件
          </button>
        </div>
      </header>

      <main
        className="mx-auto w-full max-w-5xl flex-1 py-8"
        style={{
          paddingLeft: 'calc(1rem + env(safe-area-inset-left))',
          paddingRight: 'calc(1rem + env(safe-area-inset-right))',
        }}
      >
        {/* Toolbar — glass chips */}
        {scripts.length > 0 && onDeleteAll && (
          <div className="mb-4 flex items-center gap-3 text-xs text-white/35">
            <span>{scripts.length} 篇</span>
            <div className="flex items-center gap-1 rounded-full glass-button px-1 py-0.5">
              <ArrowUpDown size={11} />
              {SORT_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    if (sort === opt.value) setAsc((v) => !v);
                    else { setSort(opt.value); setAsc(false); }
                  }}
                  className={`rounded-full px-2 py-0.5 font-medium transition-colors ${sort === opt.value ? 'bg-white/15 text-white' : 'text-white/40 hover:text-white/70'}`}
                >
                  {opt.label}{sort === opt.value ? (asc ? ' ↑' : ' ↓') : ''}
                </button>
              ))}
            </div>
            <button
              onClick={() => setConfirmClear(true)}
              className="ml-auto flex items-center gap-1 text-white/30 transition-colors hover:text-red-400"
            >
              <Trash2 size={13} className="text-red-400/70" /> 清空全部
            </button>
          </div>
        )}

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 text-center">
            <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-3xl bg-white/5 text-white/15">
              <FileText size={32} />
            </div>
            <p className="text-white/35">还没有稿件，点击右上角「新建稿件」去新建第一篇提词脚本吧</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {filtered.map((s) => {
              const isFilmed = filmedIds.has(s.id);
              return (
                <div
                  key={s.id}
                  className={`group relative cursor-pointer rounded-2xl border transition-all duration-200 active:scale-[0.985] ${isFilmed
                    ? 'border-green-500/15 glass-card bg-green-500/[0.03]'
                    : 'border-white/5 glass-card hover:border-[#D4A432]/20 hover:bg-white/[0.07]'
                  }`}
                >
                  {/* Swipe-to-film action (behind card) */}
                  <div className="absolute inset-y-0 right-0 flex w-[72px] items-center justify-center rounded-r-2xl bg-green-500 text-xs font-bold text-white opacity-0 transition-opacity group-hover:opacity-0">
                    <Check size={16} />
                  </div>

                  <div className="relative p-4" onClick={() => handleOpen(s.id)}>
                    {/* Title Row */}
                    <div className="mb-2 flex items-start justify-between">
                      <div className="flex items-center gap-2 min-w-0">
                        {isFilmed && <Check size={14} className="shrink-0 text-green-400" />}
                        <h3 className={`truncate text-base font-semibold ${isFilmed ? 'text-white/50 line-through' : 'text-white'}`}>{s.title}</h3>
                      </div>
                      <div className="flex shrink-0 gap-0.5 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => { e.stopPropagation(); toggleFilmed(s.id); }}
                          className="rounded-lg p-1.5 text-white/25 hover:bg-white/10 hover:text-green-400 transition-colors"
                          aria-label={isFilmed ? '取消标记' : '标记已拍摄'}
                        >
                          <Check size={14} />
                        </button>
                        <button
                          onClick={(e) => { e.stopPropagation(); onEdit(s.id); }}
                          className="rounded-lg p-1.5 text-white/25 hover:bg-white/10 hover:text-white transition-colors"
                          aria-label="编辑稿件"
                        >
                          <Edit3 size={14} />
                        </button>
                        <button
                          data-testid={`delete-${s.id}`}
                          onClick={(e) => { e.stopPropagation(); setConfirmId(s.id); }}
                          className="rounded-lg p-1.5 text-red-400/70 hover:bg-red-500/10 hover:text-red-400 transition-colors"
                          aria-label="删除稿件"
                        >
                          <Trash2 size={14} />
                        </button>
                      </div>
                    </div>

                    {s.content && (
                      <p className={`mb-3 line-clamp-2 text-sm leading-relaxed ${isFilmed ? 'text-white/20 line-through' : 'text-white/40'}`}>{s.content}</p>
                    )}

                    <div className="flex items-center gap-2 text-[10px] text-white/25">
                      {new Date(s.updatedAt).toLocaleDateString()}
                      <span>|</span>
                      <span>{charCounts.get(s.id)}字</span>
                      <button
                        onClick={(e) => { e.stopPropagation(); handleOpen(s.id); }}
                        className="ml-auto flex items-center gap-1 rounded-full bg-[#D4A432] px-3 py-1.5 text-xs font-bold text-[#0A0A0B] active:scale-95 transition-transform"
                      >
                        开始提词
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>

      {/* Modals — glass */}
      {confirmClear && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setConfirmClear(false)} />
          <div className="relative w-full max-w-sm rounded-3xl border border-white/10 glass-surface p-8">
            <h3 className="mb-2 text-xl font-bold text-white">确认清空全部稿件？</h3>
            <p className="mb-6 text-sm text-white/40">将删除全部 {scripts.length} 篇稿件，此操作不可撤销。</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmClear(false)} className="flex-1 rounded-xl bg-white/5 py-3 text-sm font-bold text-white transition-colors hover:bg-white/10 active:scale-95">取消</button>
              <button onClick={() => { onDeleteAll?.(); setConfirmClear(false); }} className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold text-white transition-all active:scale-95">确认清空</button>
            </div>
          </div>
        </div>
      )}

      {confirmId && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setConfirmId(null)} />
          <div className="relative w-full max-w-sm rounded-3xl border border-white/10 glass-surface p-8">
            <h3 className="mb-2 text-xl font-bold text-white">确认删除稿件？</h3>
            <p className="mb-6 text-sm text-white/40">此操作不可撤销。</p>
            <div className="flex gap-3">
              <button onClick={() => setConfirmId(null)} className="flex-1 rounded-xl bg-white/5 py-3 text-sm font-bold text-white transition-colors hover:bg-white/10 active:scale-95">取消</button>
              <button onClick={() => { onDelete(confirmId); setConfirmId(null); }} className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold text-white transition-all active:scale-95">确认删除</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
