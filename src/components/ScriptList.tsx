import { useMemo, useState, useCallback, useEffect, useLayoutEffect, useRef } from 'react';
import { Search, Plus, FileText, ArrowUpDown, Trash2, Clock, Star, Folder, FolderPlus, Check } from 'lucide-react';
import { Script } from '../types';
import { countReadableChars } from '../lib/tokens';
import { SwipeableCard } from './SwipeableCard';

interface Props {
  scripts: Script[];
  filmedIds: Set<string>;
  /** 滚动速度（字/分），卡片据此显示预计口播时长 */
  speed?: number;
  /** 最近打开的稿件 id：其卡片保持金边微光，返回列表时一眼定位 */
  highlightId?: string | null;
  /** 受控过滤器（App 持有，进入播放页返回后仍停留在原文件夹）；不传则组件内部管理 */
  filter?: Filter;
  onFilterChange?: (f: Filter) => void;
  onOpen: (id: string) => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  onCreate: () => void;
  onToggleFilmed: (id: string) => void;
  onToggleStar?: (id: string) => void;
  onMoveToFolder?: (id: string, folder: string | null) => void;
  onDeleteAll?: () => void;
}

type SortKey = 'date' | 'title' | 'chars';
/** 列表过滤器：all = 全部 / starred = 星标 / 其余值 = 文件夹名 */
export type Filter = 'all' | 'starred' | string;

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

const SORT_KEY = 'prompter_sort';
const SCROLL_KEY = 'prompter_scroll';
function loadSort(): { sort: SortKey; asc: boolean } {
  try {
    const raw = localStorage.getItem(SORT_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed.sort === 'string' && typeof parsed.asc === 'boolean') {
        return { sort: parsed.sort as SortKey, asc: parsed.asc };
      }
    }
  } catch { /* noop */ }
  return { sort: 'date', asc: false };
}

export function ScriptList({ scripts, filmedIds, speed, highlightId, filter: filterProp, onFilterChange, onOpen, onEdit, onDelete, onCreate, onToggleFilmed, onToggleStar, onMoveToFolder, onDeleteAll }: Props) {
  const [query, setQuery] = useState('');
  const initPrefs = useMemo(() => loadSort(), []);
  const [sort, setSort] = useState<SortKey>(initPrefs.sort);
  const [asc, setAsc] = useState<boolean>(initPrefs.asc);
  const [confirmClear, setConfirmClear] = useState(false);
  const [searchFocused, setSearchFocused] = useState(false);
  // 文件夹/星标过滤与移动弹层（受控：App 传入时跨视图保持，否则内部管理）
  const [innerFilter, setInnerFilter] = useState<Filter>('all');
  const filter = filterProp ?? innerFilter;
  const setFilter = useCallback((f: Filter) => {
    setInnerFilter(f);
    onFilterChange?.(f);
  }, [onFilterChange]);
  const [movingId, setMovingId] = useState<string | null>(null);
  // 新建文件夹弹层（从「移动到文件夹」弹层进入，创建后把目标稿件移入）
  const [creatingFolder, setCreatingFolder] = useState<{ assignTo: string } | null>(null);
  const [newFolderName, setNewFolderName] = useState('');

  // FLIP：卡片 DOM 引用 + 上一帧页面坐标（页面坐标不受滚动影响）
  const cardEls = useRef(new Map<string, HTMLDivElement>());
  const prevRects = useRef(new Map<string, { x: number; y: number }>());
  const prevWidth = useRef(0);

  const charCounts = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of scripts) map.set(s.id, countReadableChars(s.content));
    return map;
  }, [scripts]);

  // 文件夹由稿件数据派生：没有稿件的文件夹自动从 chips 消失，无需单独管理实体
  const folders = useMemo(
    () => [...new Set(scripts.map((s) => s.folder).filter((f): f is string => !!f))].sort((a, b) => a.localeCompare(b, 'zh')),
    [scripts]
  );

  // 当前过滤的文件夹已无稿件（派生模型下空文件夹不存在）→ 回到「全部」
  useEffect(() => {
    if (filter !== 'all' && filter !== 'starred' && !folders.includes(filter)) setFilter('all');
  }, [folders, filter]);

  const sorted = useMemo(() => {
    const list = [...scripts];
    const dir = asc ? 1 : -1;
    if (sort === 'title') list.sort((a, b) => dir * a.title.localeCompare(b.title, 'zh'));
    else if (sort === 'chars') list.sort((a, b) => dir * ((charCounts.get(a.id) ?? 0) - (charCounts.get(b.id) ?? 0)));
    else list.sort((a, b) => dir * (b.createdAt - a.createdAt));
    // 星标稳定置顶（组内保持当前排序）
    return [...list.filter((s) => s.starred), ...list.filter((s) => !s.starred)];
  }, [scripts, sort, asc, charCounts]);

  const filtered = useMemo(() => {
    let list = sorted;
    if (filter === 'starred') list = list.filter((s) => s.starred);
    else if (filter !== 'all') list = list.filter((s) => s.folder === filter);
    const q = query.toLowerCase();
    if (q) {
      list = list.filter((s) => s.title.toLowerCase().includes(q) || s.content.toLowerCase().includes(q));
    }
    return list;
  }, [sorted, filter, query]);

  // FLIP 动画：任何导致卡片位移的渲染（删除/撤销/排序/筛选）后，
  // 从旧位置反 transform 起步再过渡到 0，产生「卡片滑入新位置」的丝滑效果。
  // 依赖留空 → 每次渲染后运行；坐标未变的卡片自动跳过。
  useLayoutEffect(() => {
    const sameWidth = prevWidth.current === window.innerWidth;
    prevWidth.current = window.innerWidth;
    const next = new Map<string, { x: number; y: number }>();
    cardEls.current.forEach((el, id) => {
      const rect = el.getBoundingClientRect();
      const pos = { x: rect.left + window.scrollX, y: rect.top + window.scrollY };
      next.set(id, pos);
      const before = sameWidth ? prevRects.current.get(id) : undefined;
      if (!before) return;
      const dx = before.x - pos.x;
      const dy = before.y - pos.y;
      if (!dx && !dy) return;
      el.style.transition = 'none';
      el.style.transform = `translate(${dx}px, ${dy}px)`;
      void el.offsetHeight; // 强制回流，让起始 transform 先生效
      el.style.transition = 'transform 0.3s cubic-bezier(0.22, 1, 0.36, 1)';
      el.style.transform = '';
    });
    prevRects.current = next;
  });

  const recentScripts = useMemo(() => {
    if (!searchFocused || query) return [];
    const ids = loadRecent();
    return ids.map((id) => scripts.find((s) => s.id === id)).filter(Boolean) as Script[];
  }, [searchFocused, query, scripts]);

  const handleOpen = useCallback((id: string) => {
    saveRecent(id);
    try { localStorage.setItem(SCROLL_KEY, String(window.scrollY)); } catch { /* noop */ }
    onOpen(id);
  }, [onOpen]);

  const handleCreateFolder = () => {
    const name = newFolderName.trim();
    if (!name || !creatingFolder) return;
    onMoveToFolder?.(creatingFolder.assignTo, name);
    setCreatingFolder(null);
  };

  // Escape closes modals
  useEffect(() => {
    if (!confirmClear && !movingId && !creatingFolder) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') { setConfirmClear(false); setMovingId(null); setCreatingFolder(null); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [confirmClear, movingId, creatingFolder]);

  // 记忆排序偏好（skip mount to avoid writing back the just-loaded defaults）
  const sortMounted = useRef(false);
  useEffect(() => {
    if (!sortMounted.current) { sortMounted.current = true; return; }
    try { localStorage.setItem(SORT_KEY, JSON.stringify({ sort, asc })); } catch { /* noop */ }
  }, [sort, asc]);

  const scrollYRef = useRef(0);

  // 恢复滚动位置
  useEffect(() => {
    const saved = localStorage.getItem(SCROLL_KEY);
    if (!saved) return;
    const y = parseInt(saved, 10);
    if (isNaN(y) || y <= 0) return;
    const raf = requestAnimationFrame(() => window.scrollTo(0, y));
    return () => cancelAnimationFrame(raf);
  }, []);

  // 实时追踪滚动位置，卸载时作为兜底写入（>0 过滤掉 StrictMode 双重挂载时的 0 写入）
  useEffect(() => {
    const onScroll = () => { scrollYRef.current = window.scrollY; };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (scrollYRef.current > 0) {
        try { localStorage.setItem(SCROLL_KEY, String(scrollYRef.current)); } catch { /* noop */ }
      }
    };
  }, []);

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
            <img src={import.meta.env.BASE_URL + 'icon.svg?v=4'} alt="" className="h-7 w-7 rounded-lg" />
            <h1 className="text-base font-bold text-white">提词器</h1>
          </div>
          <div className="relative ml-auto">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-white/40" size={14} />
            <input
              placeholder="搜索稿件..."
              value={query}
              onFocus={() => setSearchFocused(true)}
              onBlur={() => setTimeout(() => setSearchFocused(false), 150)}
              onChange={(e) => setQuery(e.target.value)}
              className="h-10 w-28 rounded-full border border-white/10 bg-white/5 pl-8 pr-2.5 text-sm text-white placeholder-white/30 transition-all focus:w-48 focus:border-[#D4A432]/40 focus:bg-white/10 focus:outline-none sm:w-48"
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
            onClick={() => {
              try { localStorage.setItem(SCROLL_KEY, String(window.scrollY)); } catch { /* noop */ }
              onCreate();
            }}
            className="flex h-10 shrink-0 items-center gap-1.5 rounded-full bg-[#D4A432] px-3.5 text-sm font-bold text-[#0A0A0B] transition-all active:scale-95"
          >
            <Plus size={15} />新建稿件
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
        {/* Filter Chips — 全部 / 星标 / 文件夹（横向滚动）。
            文件夹由稿件派生（无实体管理），新建入口在卡片的「移动到文件夹」弹层里 */}
        {scripts.length > 0 && (
          <div className="mb-4 flex items-center gap-2 overflow-x-auto pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            <FilterChip active={filter === 'all'} onClick={() => setFilter('all')}>
              全部
              <span className="rounded-full bg-white/12 px-1.5 text-[11px] font-semibold tabular-nums text-white/55">
                {scripts.length}
              </span>
            </FilterChip>
            <FilterChip active={filter === 'starred'} onClick={() => setFilter('starred')}>
              <Star size={13} className={filter === 'starred' ? 'fill-current' : ''} />
              星标
            </FilterChip>
            {folders.map((f) => (
              <FilterChip key={f} active={filter === f} onClick={() => setFilter(f)}>
                <Folder size={13} />
                {f}
                <span className="rounded-full bg-white/12 px-1.5 text-[11px] font-semibold tabular-nums text-white/55">
                  {scripts.filter((s) => s.folder === f).length}
                </span>
              </FilterChip>
            ))}
          </div>
        )}

        {/* Toolbar — T3 工具操作（32px 玻璃胶囊） */}
        {scripts.length > 0 && onDeleteAll && (
          <div className="mb-5 flex items-center gap-1.5">
            <ArrowUpDown size={13} className="mx-1 shrink-0 text-white/25" />
            {SORT_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                onClick={() => {
                  if (sort === opt.value) setAsc((v) => !v);
                  else { setSort(opt.value); setAsc(false); }
                }}
                className={`flex h-[var(--ctl-3-h)] shrink-0 items-center whitespace-nowrap rounded-full px-3 text-[13px] font-medium transition-colors ${
                  sort === opt.value
                    ? 'bg-white/15 text-white'
                    : 'chip-glass text-white/40 hover:text-white/70'
                }`}
              >
                {opt.label}{sort === opt.value ? (asc ? ' ↑' : ' ↓') : ''}
              </button>
            ))}

            <button
              onClick={() => setConfirmClear(true)}
              className="ml-auto flex h-[var(--ctl-3-h)] shrink-0 items-center gap-1.5 rounded-full px-3 text-[13px] font-medium text-[#D4A432]/80 transition-colors hover:bg-[#D4A432]/15 hover:text-[#D4A432] active:scale-95"
            >
              <Trash2 size={13} /> 清空全部
            </button>
          </div>
        )}

        {filtered.length === 0 ? (
          scripts.length === 0 ? (
            /* true empty — reason only, no duplicate create action */
            <div className="flex flex-col items-center justify-center py-24 text-center">
              <FileText size={40} className="mb-4 text-white/10" />
              <p className="text-sm text-white/30">暂无稿件</p>
            </div>
          ) : query ? (
            /* filtered-empty — search miss */
            <div className="flex flex-col items-center justify-center py-24 text-center">
              <Search size={40} className="mb-4 text-white/10" />
              <p className="text-sm text-white/30">未找到与「{query}」匹配的稿件</p>
              <button onClick={() => setQuery('')} className="mt-3 rounded-full px-4 py-1.5 text-xs text-white/40 transition-colors hover:bg-white/10 hover:text-white/60">清除搜索</button>
            </div>
          ) : (
            /* folder-empty — 该过滤条件下没有稿件（派生模型下很快被守卫弹回「全部」，兜底展示） */
            <div className="flex flex-col items-center justify-center py-24 text-center">
              <Folder size={40} className="mb-4 text-white/10" />
              <p className="text-sm text-white/30">
                {filter === 'starred' ? '还没有星标稿件，点击卡片右下角的星标收藏' : `「${filter}」中没有稿件`}
              </p>
              <button onClick={() => setFilter('all')} className="mt-3 rounded-full px-4 py-1.5 text-xs text-white/40 transition-colors hover:bg-white/10 hover:text-white/60">查看全部</button>
            </div>
          )
        ) : (
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {filtered.map((s) => (
              <div
                key={s.id}
                ref={(el) => {
                  if (el) cardEls.current.set(s.id, el);
                  else cardEls.current.delete(s.id);
                }}
              >
                <SwipeableCard
                  script={s}
                  isFilmed={filmedIds.has(s.id)}
                  charCount={charCounts.get(s.id) ?? 0}
                  speed={speed}
                  starred={!!s.starred}
                  highlighted={s.id === highlightId}
                  onToggleStar={onToggleStar ? () => onToggleStar(s.id) : undefined}
                  onOpenFolderPicker={onMoveToFolder ? () => setMovingId(s.id) : undefined}
                  onOpen={handleOpen}
                  onEdit={onEdit}
                  onDelete={onDelete}
                  onToggleFilmed={onToggleFilmed}
                />
              </div>
            ))}
          </div>
        )}
      </main>

      {/* Confirm Clear All — Header / Body / Footer */}
      {confirmClear && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setConfirmClear(false)} />
          <div className="relative flex w-full max-w-sm flex-col overflow-hidden rounded-3xl border border-white/10 glass-surface">
            <header className="shrink-0 px-8 pt-8">
              <h3 className="text-xl font-bold text-white">确认清空全部稿件？</h3>
            </header>
            <div className="overflow-y-auto px-8 py-3">
              <p className="text-sm text-white/40">将删除全部 {scripts.length} 篇稿件，此操作不可撤销。</p>
            </div>
            <footer className="shrink-0 flex gap-3 px-8 pb-8 pt-2">
              <button onClick={() => setConfirmClear(false)} className="flex-1 rounded-xl bg-white/5 py-3 text-sm font-bold text-white transition-colors hover:bg-white/10 active:scale-95">取消</button>
              <button onClick={() => { onDeleteAll?.(); setConfirmClear(false); }} className="flex-1 rounded-xl bg-red-500 py-3 text-sm font-bold text-white transition-all active:scale-95">确认清空</button>
            </footer>
          </div>
        </div>
      )}

      {/* Move To Folder Sheet */}
      {movingId && (
        <div className="fixed inset-0 z-[100] flex items-end justify-center p-4 sm:items-center">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setMovingId(null)} />
          <div data-testid="folder-sheet" className="relative flex max-h-[70vh] w-full max-w-sm flex-col overflow-hidden rounded-3xl border border-white/10 glass-surface">
            <header className="shrink-0 px-6 pt-6 pb-2">
              <h3 className="flex items-center gap-2 text-base font-bold text-white">
                <Folder size={16} className="text-white/40" />移动到文件夹
              </h3>
            </header>
            <div className="flex-1 overflow-y-auto p-3">
              <FolderOption
                label="未分组"
                active={!scripts.find((s) => s.id === movingId)?.folder}
                onClick={() => { onMoveToFolder?.(movingId, null); setMovingId(null); }}
              />
              {folders.map((f) => (
                <FolderOption
                  key={f}
                  label={f}
                  count={scripts.filter((s) => s.folder === f).length}
                  active={scripts.find((s) => s.id === movingId)?.folder === f}
                  onClick={() => { onMoveToFolder?.(movingId, f); setMovingId(null); }}
                />
              ))}
              <FolderOption
                label="＋ 新建文件夹…"
                isNew
                onClick={() => { setNewFolderName(''); setCreatingFolder({ assignTo: movingId }); setMovingId(null); }}
              />
            </div>
          </div>
        </div>
      )}

      {/* Create Folder Dialog */}
      {creatingFolder && (
        <div className="fixed inset-0 z-[110] flex items-center justify-center p-4">
          <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" onClick={() => setCreatingFolder(null)} />
          <div className="relative flex w-full max-w-sm flex-col overflow-hidden rounded-3xl border border-white/10 glass-surface">
            <header className="shrink-0 px-6 pt-6">
              <h3 className="flex items-center gap-2 text-base font-bold text-white">
                <FolderPlus size={16} className="text-white/40" />新建文件夹
              </h3>
            </header>
            <div className="px-6 py-4">
              <input
                autoFocus
                value={newFolderName}
                onChange={(e) => setNewFolderName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.nativeEvent.isComposing) return; // 中文输入法选字回车不当作提交
                  if (e.key === 'Enter') handleCreateFolder();
                }}
                placeholder="文件夹名称"
                className="w-full rounded-lg border border-white/5 bg-white/5 px-3 py-2.5 text-sm text-white placeholder-white/30 transition-colors focus:border-[#D4A432] focus:outline-none"
              />
            </div>
            <footer className="shrink-0 flex gap-3 px-6 pb-6 pt-1">
              <button onClick={() => setCreatingFolder(null)} className="flex-1 rounded-xl bg-white/5 py-3 text-sm font-bold text-white transition-colors hover:bg-white/10 active:scale-95">取消</button>
              <button
                onClick={handleCreateFolder}
                disabled={!newFolderName.trim()}
                className="flex-1 rounded-xl bg-[#D4A432] py-3 text-sm font-bold text-[#0A0A0B] transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-30"
              >
                创建
              </button>
            </footer>
          </div>
        </div>
      )}

    </div>
  );
}

/** 过滤 chip（T2 内容导航 · 40px/14px）。选中态与排序 chips 一致（bg-white/15 高亮）。编辑页分组行复用 */
export function FilterChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`flex h-[var(--ctl-2-h)] shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-4 text-sm font-medium transition-colors ${
        active ? 'bg-white/15 text-white' : 'chip-glass text-white/45 hover:text-white/80'
      }`}
    >
      {children}
    </button>
  );
}

/** 文件夹选项行（移动弹层内） */
function FolderOption({ label, count, active, isNew, onClick }: {
  label: string;
  count?: number;
  active?: boolean;
  isNew?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex w-full items-center justify-between rounded-xl px-3 py-3 text-left text-sm transition-colors hover:bg-white/10 active:scale-[0.98]"
    >
      <span className={`flex min-w-0 items-center gap-2 ${isNew ? 'text-[#D4A432]' : active ? 'text-white' : 'text-white/70'}`}>
        <span className="min-w-0 truncate">{label}</span>
      </span>
      <span className="flex shrink-0 items-center gap-2">
        {count !== undefined && <span className="text-xs text-white/25">{count}</span>}
        {active && <Check size={14} className="text-[#D4A432]" />}
      </span>
    </button>
  );
}
