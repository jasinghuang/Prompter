import { useMemo, useState, useEffect, useRef } from 'react';
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
  // Track whether items are ready for stagger animation
  const [mounted, setMounted] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    // Trigger staggered reveal after mount
    const frame = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(frame);
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

  return (
    <div className="flex min-h-screen flex-col bg-[#0A0A0B] text-[#F5F5F5]">
      {/* Header */}
      <header
        className="sticky top-0 z-50 border-b border-[#26262B] bg-[#0A0A0B]/70 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))] backdrop-blur-xl"
        style={{
          paddingLeft: 'calc(0.75rem + env(safe-area-inset-left))',
          paddingRight: 'calc(0.75rem + env(safe-area-inset-right))',
        }}
      >
        <div className="mx-auto flex max-w-[70rem] items-center gap-3">
          <div className="flex items-center gap-2">
            <img src="/icon.svg" alt="" className="h-7 w-7 rounded-lg" />
            <h1 className="text-base font-bold text-[#F5F5F5]">提词器</h1>
          </div>
          <div className="relative ml-auto">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[#71717A]" size={14} />
            <input
              placeholder="搜索稿件..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-28 rounded-full border border-[#26262B] bg-[#1A1A1F] py-2 pl-8 pr-2.5 text-sm text-[#F5F5F5] placeholder-[#71717A] transition-all duration-200 focus:w-48 focus:border-[#D4A432] focus:outline-none focus:ring-2 focus:ring-[rgba(212,164,50,0.15)] sm:w-48"
            />
          </div>
          <button
            onClick={onCreate}
            className="btn-spring btn-press flex shrink-0 items-center gap-1.5 rounded-full bg-[#D4A432] px-4 py-2.5 text-xs font-bold text-[#0A0A0B] focus-ring active:scale-[0.97] active:translate-y-px sm:gap-2 sm:text-sm"
            style={{ minHeight: '44px' }}
          >
            <Plus size={16} />新建稿件
          </button>
        </div>
      </header>

      {/* Main Content */}
      <main
        className="mx-auto w-full max-w-[70rem] flex-1 py-8"
        style={{
          paddingLeft: 'calc(1rem + env(safe-area-inset-left))',
          paddingRight: 'calc(1rem + env(safe-area-inset-right))',
        }}
      >
        {/* Toolbar: Sort + Count */}
        {scripts.length > 0 && onDeleteAll && (
          <div className="mb-6 flex items-center gap-3 text-xs text-[#71717A]">
            <span className="font-mono tabular-nums">{scripts.length} 篇</span>
            <div className="flex items-center gap-1">
              <ArrowUpDown size={11} className="text-[#71717A]" />
              {SORT_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => {
                    if (sort === opt.value) setAsc((v) => !v);
                    else {
                      setSort(opt.value);
                      setAsc(false);
                    }
                  }}
                  className={`btn-spring rounded-md px-2 py-0.5 font-medium transition-colors focus-ring ${
                    sort === opt.value
                      ? 'text-[#D4A432] bg-[rgba(212,164,50,0.12)]'
                      : 'text-[#71717A] hover:text-[#A1A1AA]'
                  }`}
                >
                  {opt.label}
                  {sort === opt.value ? (asc ? ' ↑' : ' ↓') : ''}
                </button>
              ))}
            </div>
            <button
              onClick={() => setConfirmClear(true)}
              className="ml-auto flex items-center gap-1 text-[#71717A] transition-colors hover:text-[#DC2626] focus-ring rounded-md px-1"
            >
              <Trash2 size={13} /> 清空全部
            </button>
          </div>
        )}

        {/* Empty State */}
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 text-center">
            <div className="mb-5 flex h-16 w-16 items-center justify-center rounded-3xl bg-[#1A1A1F] text-[#71717A]">
              <FileText size={32} />
            </div>
            {scripts.length === 0 ? (
              <>
                <p className="mb-2 text-base font-medium text-[#A1A1AA]">还没有稿件</p>
                <p className="text-sm text-[#71717A]">点击右上角「新建稿件」创建你的第一篇提词脚本</p>
              </>
            ) : (
              <p className="text-sm text-[#A1A1AA]">未找到与「{query}」匹配的稿件</p>
            )}
          </div>
        ) : (
          /* Script Grid — 2 columns max, single column on mobile */
          <div ref={listRef} className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            {filtered.map((s, i) => (
              <div
                key={s.id}
                onClick={() => onOpen(s.id)}
                className="card-spring group relative cursor-pointer rounded-2xl border border-[#26262B] bg-[#131316] p-5 transition-all hover:border-[rgba(212,164,50,0.15)] hover:bg-[#1A1A1F] active:scale-[0.985] focus-ring"
                style={{
                  opacity: mounted ? 1 : 0,
                  animation: mounted
                    ? `slide-up-reveal 0.4s cubic-bezier(0.22, 1, 0.36, 1) forwards`
                    : 'none',
                  animationDelay: mounted ? `${i * 50}ms` : '0ms',
                }}
                role="button"
                tabIndex={0}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    onOpen(s.id);
                  }
                }}
              >
                {/* Title Row */}
                <div className="mb-2.5 flex items-start justify-between">
                  <h3 className="truncate text-base font-semibold text-[#F5F5F5]">{s.title}</h3>
                  <div className="flex shrink-0 gap-0.5 opacity-0 transition-opacity duration-200 group-hover:opacity-100 sm:opacity-0">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onEdit(s.id);
                      }}
                      className="btn-spring rounded-lg p-1.5 text-[#71717A] hover:bg-[rgba(212,164,50,0.08)] hover:text-[#D4A432] focus-ring"
                      aria-label="编辑稿件"
                    >
                      <Edit3 size={14} />
                    </button>
                    <button
                      data-testid={`delete-${s.id}`}
                      onClick={(e) => {
                        e.stopPropagation();
                        setConfirmId(s.id);
                      }}
                      className="btn-spring rounded-lg p-1.5 text-[#71717A] hover:bg-[rgba(220,38,38,0.12)] hover:text-[#DC2626] focus-ring"
                      aria-label="删除稿件"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>

                {/* Content Preview */}
                {s.content && (
                  <p className="mb-3 line-clamp-2 text-sm leading-relaxed text-[#A1A1AA]">
                    {s.content}
                  </p>
                )}

                {/* Footer */}
                <div className="flex items-center gap-2 border-t border-[#26262B] pt-3 text-[11px] text-[#71717A]">
                  <time dateTime={new Date(s.updatedAt).toISOString()} className="font-mono tabular-nums">
                    {new Date(s.updatedAt).toLocaleDateString()}
                  </time>
                  <span aria-hidden="true">·</span>
                  <span className="font-mono tabular-nums">{charCounts.get(s.id)}字</span>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onOpen(s.id);
                    }}
                    className="btn-spring btn-press ml-auto flex items-center gap-1.5 rounded-full bg-[#D4A432] px-3.5 py-2 text-xs font-bold text-[#0A0A0B] active:scale-[0.97] active:translate-y-px focus-ring"
                    style={{ minHeight: '44px' }}
                  >
                    开始提词 <Play size={11} fill="currentColor" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* Confirm Clear All Modal */}
      {confirmClear && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div
            className="absolute inset-0 bg-[#0A0A0B]/80 backdrop-blur-sm"
            onClick={() => setConfirmClear(false)}
          />
          <div
            className="animate-scale-up relative w-full max-w-sm rounded-3xl border border-[#26262B] bg-[#131316] p-8 shadow-2xl"
            role="alertdialog"
            aria-modal="true"
            aria-label="确认清空全部稿件"
          >
            <h3 className="mb-2 text-xl font-bold text-[#F5F5F5]">确认清空全部稿件？</h3>
            <p className="mb-6 text-sm leading-relaxed text-[#A1A1AA]">
              将删除全部 {scripts.length} 篇稿件，此操作不可撤销。
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setConfirmClear(false)}
                className="btn-spring flex-1 rounded-xl border border-[#26262B] bg-transparent py-3 text-sm font-semibold text-[#A1A1AA] hover:bg-[#1A1A1F] hover:text-[#F5F5F5] focus-ring"
                style={{ minHeight: '44px' }}
              >
                取消
              </button>
              <button
                onClick={() => {
                  onDeleteAll?.();
                  setConfirmClear(false);
                }}
                className="btn-spring btn-press flex-1 rounded-xl bg-[#DC2626] py-3 text-sm font-bold text-white active:scale-[0.97] focus-ring"
                style={{ minHeight: '44px' }}
              >
                确认清空
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Confirm Delete Single Modal */}
      {confirmId && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
          <div
            className="absolute inset-0 bg-[#0A0A0B]/80 backdrop-blur-sm"
            onClick={() => setConfirmId(null)}
          />
          <div
            className="animate-scale-up relative w-full max-w-sm rounded-3xl border border-[#26262B] bg-[#131316] p-8 shadow-2xl"
            role="alertdialog"
            aria-modal="true"
            aria-label="确认删除稿件"
          >
            <h3 className="mb-2 text-xl font-bold text-[#F5F5F5]">确认删除稿件？</h3>
            <p className="mb-6 text-sm leading-relaxed text-[#A1A1AA]">
              此操作不可撤销。
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setConfirmId(null)}
                className="btn-spring flex-1 rounded-xl border border-[#26262B] bg-transparent py-3 text-sm font-semibold text-[#A1A1AA] hover:bg-[#1A1A1F] hover:text-[#F5F5F5] focus-ring"
                style={{ minHeight: '44px' }}
              >
                取消
              </button>
              <button
                onClick={() => {
                  onDelete(confirmId);
                  setConfirmId(null);
                }}
                className="btn-spring btn-press flex-1 rounded-xl bg-[#DC2626] py-3 text-sm font-bold text-white active:scale-[0.97] focus-ring"
                style={{ minHeight: '44px' }}
              >
                确认删除
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
