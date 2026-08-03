import { useMemo, useState, useRef, useCallback, useLayoutEffect } from 'react';
import { Search, Plus, FileText, Edit3, Trash2, ArrowUpDown, Check, Clock, X } from 'lucide-react';
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

  const sortIdx = SORT_OPTIONS.findIndex((o) => o.value === sort);
  const sortPillRef = useRef<HTMLDivElement | null>(null);
  const sortContainerRef = useRef<HTMLDivElement | null>(null);

  // Position pill to exactly cover active button via getBoundingClientRect
  useLayoutEffect(() => {
    const container = sortContainerRef.current;
    const pill = sortPillRef.current;
    if (!container || !pill) return;
    const btn = container.querySelector<HTMLButtonElement>(
      `[data-sort-value="${SORT_OPTIONS[sortIdx].value}"]`
    );
    if (!btn) return;
    const cr = container.getBoundingClientRect();
    const br = btn.getBoundingClientRect();
    pill.style.left = `${br.left - cr.left}px`;
    pill.style.width = `${br.width}px`;
  }, [sortIdx, asc]);

  // Swipe-to-film: touch gesture tracking
  const swipeRef = useRef<Map<string, number>>(new Map());
  const [swipeOffsets, setSwipeOffsets] = useState<Record<string, number>>({});
  const touchStartX = useRef(0);
  const touchStartY = useRef(0);
  const swipingId = useRef<string | null>(null);

  const setSwipe = useCallback((id: string, offset: number) => {
    swipeRef.current.set(id, offset);
    setSwipeOffsets((prev) => ({ ...prev, [id]: offset }));
  }, []);

  const handleTouchStart = useCallback((e: React.TouchEvent, id: string) => {
    touchStartX.current = e.touches[0].clientX;
    touchStartY.current = e.touches[0].clientY;
    swipingId.current = id;
  }, []);

  const handleTouchMove = useCallback((e: React.TouchEvent, id: string) => {
    if (swipingId.current !== id) return;
    const dx = e.touches[0].clientX - touchStartX.current;
    const dy = e.touches[0].clientY - touchStartY.current;
    if (Math.abs(dy) > Math.abs(dx)) return; // ignore vertical scroll
    // Right swipe → filmed (green on left), left swipe → delete (red on right)
    setSwipe(id, Math.max(-72, Math.min(72, dx)));
  }, [setSwipe]);

  const handleTouchEnd = useCallback((_e: React.TouchEvent, id: string) => {
    if (swipingId.current !== id) { swipingId.current = null; return; }
    swipingId.current = null;
    const offset = swipeRef.current.get(id) || 0;
    if (offset > 40) {
      // Right swipe → mark filmed
      toggleFilmed(id);
    } else if (offset < -40) {
      // Left swipe → trigger delete confirmation
      setConfirmId(id);
    }
    setSwipe(id, 0);
  }, [setSwipe, toggleFilmed]);

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

            {/* Sort — sliding pill via getBoundingClientRect */}
            <div
              ref={sortContainerRef}
              className="relative flex items-center rounded-full glass-button py-0.5 pl-2 pr-1"
            >
              <ArrowUpDown size={11} className="mr-1.5 shrink-0 text-white/30" />
              <div
                ref={sortPillRef}
                className="absolute top-0.5 rounded-full bg-white/15 transition-all duration-300 ease-out"
                style={{ height: 'calc(100% - 4px)' }}
              />
              {SORT_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  data-sort-value={opt.value}
                  onClick={() => {
                    if (sort === opt.value) setAsc((v) => !v);
                    else { setSort(opt.value); setAsc(false); }
                  }}
                  className={`relative z-10 whitespace-nowrap rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                    sort === opt.value
                      ? 'text-white'
                      : 'text-white/35 hover:text-white/60'
                  }`}
                >
                  {opt.label}{sort === opt.value ? (asc ? '↑' : '↓') : ''}
                </button>
              ))}
            </div>

            <button
              onClick={() => setConfirmClear(true)}
              className="ml-auto flex items-center gap-1.5 rounded-full border border-red-400/15 bg-red-500/10 px-3 py-1 text-red-400/80 transition-all hover:bg-red-500/20 hover:text-red-300 active:scale-95"
            >
              <Trash2 size={12} /> 清空全部
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
              const swipeX = swipeOffsets[s.id] || 0;

              return (
                <div
                  key={s.id}
                  className={`group relative overflow-hidden rounded-2xl border transition-colors duration-200 ${isFilmed
                    ? 'border-green-500/15 glass-card bg-green-500/[0.03]'
                    : 'border-[#D4A432]/15 glass-card hover:border-[#D4A432]/50 hover:bg-white/[0.07]'
                  }`}
                  onTouchStart={(e) => handleTouchStart(e, s.id)}
                  onTouchMove={(e) => handleTouchMove(e, s.id)}
                  onTouchEnd={(e) => handleTouchEnd(e, s.id)}
                >
                  {/* Right swipe (→): filmed action on the left */}
                  <div className="absolute inset-y-0 left-0 flex w-[72px] items-center justify-center rounded-l-2xl transition-opacity duration-200"
                    style={{
                      background: swipeX > 20 ? (isFilmed ? '#52525B' : '#22C55E') : 'transparent',
                      opacity: swipeX > 20 ? 1 : 0,
                    }}
                  >
                    {isFilmed ? (
                      <X size={20} strokeWidth={3} className="text-white" />
                    ) : (
                      <Check size={20} strokeWidth={3} className="text-white" />
                    )}
                  </div>

                  {/* Left swipe (←): red "删除" on the right */}
                  <div className="absolute inset-y-0 right-0 flex w-[72px] items-center justify-center rounded-r-2xl transition-opacity duration-200"
                    style={{ background: swipeX < -20 ? '#DC2626' : 'transparent', opacity: swipeX < -20 ? 1 : 0 }}
                  >
                    <Trash2 size={20} strokeWidth={2.5} className="text-white" />
                  </div>

                  {/* Card content — slides on swipe */}
                  <div
                    className="relative p-4"
                    style={{
                      transform: `translateX(${swipeX}px)`,
                      transition: swipingId.current === s.id ? 'none' : 'transform 0.25s ease-out',
                    }}
                    onClick={() => {
                      if (swipingId.current) return;
                      handleOpen(s.id);
                    }}
                  >
                    {/* Title Row */}
                    <div className="mb-2 flex items-start justify-between">
                      <div className="flex items-center gap-2 min-w-0">
                        {isFilmed && <Check size={14} className="shrink-0 text-green-400" />}
                        <h3 className={`truncate text-base font-semibold ${isFilmed ? 'text-white/50 line-through' : 'text-white'}`}>{s.title}</h3>
                      </div>
                      {/* Action buttons — always visible with glass backgrounds */}
                      <div className="flex shrink-0 gap-1.5 ml-2">
                        <button
                          onClick={(e) => { e.stopPropagation(); onEdit(s.id); }}
                          className="flex items-center justify-center rounded-lg bg-white/10 px-2.5 py-1.5 text-xs text-white/60 transition-colors hover:bg-white/20 hover:text-white active:scale-95"
                          aria-label="编辑稿件"
                        >
                          <Edit3 size={13} />
                        </button>
                        <button
                          data-testid={`delete-${s.id}`}
                          onClick={(e) => { e.stopPropagation(); setConfirmId(s.id); }}
                          className="flex items-center justify-center rounded-lg bg-red-500/15 px-2.5 py-1.5 text-xs text-red-400 transition-colors hover:bg-red-500/25 hover:text-red-300 active:scale-95"
                          aria-label="删除稿件"
                        >
                          <Trash2 size={13} />
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
