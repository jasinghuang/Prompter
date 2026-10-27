import { useState, useEffect, useRef, useMemo } from 'react';
import { Undo2 } from 'lucide-react';
import { useTransientFlag } from './hooks/useTransientFlag';
import { ScriptList, type Filter } from './components/ScriptList';
import { ScriptEditor } from './components/ScriptEditor';
import { Teleprompter } from './components/Teleprompter';
import { AddToHomeScreenPrompt } from './components/AddToHomeScreenPrompt';
import { useScripts } from './store/useScripts';
import { useSettings } from './store/useSettings';
import { useFilmed } from './store/useFilmed';
import { Script } from './types';
import { resolveIndexAfterEdit } from './lib/editResolve';
import { splitByParagraphs, splitByKeyword } from './lib/split';

type View = 'list' | 'prompter' | 'editor';

const POS_KEY = 'prompter_pos_';

/** 撤销删除的快照与展示时长（支持单篇与整批） */
const UNDO_WINDOW_MS = 2000;
interface DeletedSnapshot {
  script: Script;
  index: number;
  wasFilmed: boolean;
}
interface UndoableDelete {
  items: DeletedSnapshot[];
}

function loadPosition(id: string): number {
  try {
    const v = localStorage.getItem(POS_KEY + id);
    return v ? parseInt(v, 10) : 0;
  } catch { return 0; }
}

function savePosition(id: string, index: number) {
  try { localStorage.setItem(POS_KEY + id, String(index)); } catch { /* quota exceeded */ }
}

export default function App() {
  const { scripts, addScript, updateScript, deleteScript, restoreScript, toggleStar, moveToFolder, clearAll, importScript } = useScripts();
  const { settings, updateSettings } = useSettings();
  const { filmedIds, markFilmed, toggleFilmed, clearStale } = useFilmed();

  const [view, setView] = useState<View>('list');
  const [activeId, setActiveId] = useState<string | null>(null);
  // 最近打开的稿件：返回列表时其卡片保持高亮，一眼找回位置（会话级）
  const [lastOpenedId, setLastOpenedId] = useState<string | null>(null);
  // 列表过滤器提升到 App：进播放页返回后仍停留在原文件夹（会话级）
  const [listFilter, setListFilter] = useState<Filter>('all');
  // 提词器当前阅读位置（受控，供编辑返回定位使用）
  const [prompterIndex, setPrompterIndex] = useState(0);
  // 从提词器进入编辑时的快照
  const [editSnapshot, setEditSnapshot] = useState<{ content: string; index: number } | null>(null);
  const [resetNotice, showResetNotice] = useTransientFlag(3000);
  // 删除撤销：快照 + 2 秒展示窗口
  const [undoable, setUndoable] = useState<UndoableDelete | null>(null);
  const undoTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const active = scripts.find((s) => s.id === activeId) ?? null;

  // 全部文件夹（由稿件派生，供编辑页分组选择）
  const folders = useMemo(
    () => [...new Set(scripts.map((s) => s.folder).filter((f): f is string => !!f))].sort((a, b) => a.localeCompare(b, 'zh')),
    [scripts]
  );

  useEffect(() => {
    return () => {
      if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    };
  }, []);

  const handleDeleteScripts = (ids: string[]) => {
    const items: DeletedSnapshot[] = [];
    for (const id of ids) {
      const index = scripts.findIndex((s) => s.id === id);
      if (index === -1) continue;
      items.push({ script: scripts[index], index, wasFilmed: filmedIds.has(id) });
    }
    if (!items.length) return;
    ids.forEach((id) => deleteScript(id));
    setUndoable({ items });
    if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    undoTimerRef.current = setTimeout(() => setUndoable(null), UNDO_WINDOW_MS);
  };

  const handleUndoDelete = () => {
    if (!undoable) return;
    if (undoTimerRef.current) clearTimeout(undoTimerRef.current);
    // 按原索引升序回插，逐一还原到删除前的位置
    const ordered = [...undoable.items].sort((a, b) => a.index - b.index);
    for (const item of ordered) {
      restoreScript(item.script, item.index);
      if (item.wasFilmed) markFilmed(item.script.id); // clearStale 会清掉已删稿的标记，撤销时补回
    }
    setUndoable(null);
  };

  // 清理已删除稿件的 filmed 残留 id
  useEffect(() => {
    clearStale(scripts.map((s) => s.id));
  }, [scripts, clearStale]);

  // 编辑/提词中防误退出（桌面端有效，移动端受限）
  useEffect(() => {
    const handler = (e: BeforeUnloadEvent) => {
      if (view !== 'list') {
        e.preventDefault();
        e.returnValue = '';
      }
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [view]);

  const openPrompter = (id: string) => {
    setActiveId(id);
    setLastOpenedId(id);
    setPrompterIndex(loadPosition(id));
    setEditSnapshot(null);
    setView('prompter');
  };

  const openEditorFromPrompter = () => {
    if (!active) return;
    setEditSnapshot({ content: active.content, index: prompterIndex });
    setView('editor');
  };

  const handleCreate = () => {
    const id = addScript();
    setActiveId(id);
    setEditSnapshot(null);
    setView('editor');
  };

  const handleSplit = (content: string) => {
    if (!active) return;
    const segments =
      settings.splitMode === 'keyword' && settings.splitKeyword
        ? splitByKeyword(content, settings.splitKeyword)
        : splitByParagraphs(content);
    if (segments.length < 2) return;
    for (const seg of segments) {
      const lines = seg.split('\n');
      const title = lines[0].trim();
      importScript(title, seg, active.folder); // 拆分产物继承父稿件分组
    }
    deleteScript(active.id);
    setView('list');
  };

  if (view === 'prompter' && active) {
    return (
      <>
        <Teleprompter
          script={active}
          settings={settings}
          index={prompterIndex}
          onIndexChange={(i) => { setPrompterIndex(i); savePosition(active.id, i); }}
          onChangeSettings={updateSettings}
          onBack={() => setView('list')}
          onEdit={openEditorFromPrompter}
          onCompleted={() => markFilmed(active.id)}
          isFilmed={filmedIds.has(active.id)}
          onToggleFilmed={() => toggleFilmed(active.id)}
        />
        {resetNotice && (
          <div className="fixed left-1/2 top-20 z-[120] -translate-x-1/2 rounded-full border border-white/10 glass-surface px-4 py-2.5 text-center text-xs text-[#D4A432] shadow-2xl">
            文案改动已跨越当前位置，已重置到开头
          </div>
        )}
      </>
    );
  }

  if (view === 'editor' && active) {
    return (
      <ScriptEditor
        script={active}
        folder={active.folder}
        folders={folders}
        onFolderChange={(f) => moveToFolder(active.id, f)}
        pauseKeyword={settings.pauseKeyword}
        onPauseKeywordChange={(kw) => updateSettings({ pauseKeyword: kw })}
        pauseOnParagraph={settings.pauseOnParagraph}
        onPauseOnParagraphChange={(v) => updateSettings({ pauseOnParagraph: v })}
        splitMode={settings.splitMode}
        onSplitModeChange={(m) => updateSettings({ splitMode: m })}
        splitKeyword={settings.splitKeyword}
        onSplitKeywordChange={(kw) => updateSettings({ splitKeyword: kw })}
        onSave={(id, title, content) => {
          updateScript(id, title, content);
          // 从提词器进入编辑的情形：判断返回后定位
          if (editSnapshot) {
            const newIndex = resolveIndexAfterEdit(editSnapshot.content, content, editSnapshot.index);
            if (newIndex === 0 && editSnapshot.index !== 0) {
              showResetNotice();
            }
            setPrompterIndex(newIndex);
            setEditSnapshot({ content, index: newIndex });
          }
        }}
        onBack={() => setView(editSnapshot ? 'prompter' : 'list')}
        onSplit={handleSplit}
      />
    );
  }

  return (
    <>
      <ScriptList
        scripts={scripts}
        filmedIds={filmedIds}
        speed={settings.scrollSpeed}
        highlightId={lastOpenedId}
        filter={listFilter}
        onFilterChange={setListFilter}
        onOpen={openPrompter}
        onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
        onDelete={(id) => handleDeleteScripts([id])}
        onCreate={handleCreate}
        onToggleFilmed={toggleFilmed}
        onToggleStar={toggleStar}
        onMoveToFolder={moveToFolder}
        onBatchDelete={handleDeleteScripts}
        onDeleteAll={clearAll}
      />
      {/* 撤销删除（2 秒窗口，置顶显示）。
          居中用 inset-x-0 mx-auto w-fit，不用 translate —— Tailwind v4 的
          translate 工具类是独立 translate 属性，会和 keyframe 里的 transform 叠加导致跳动 */}
      {undoable && (
        <div className="toast-in pointer-events-none fixed inset-x-0 top-[calc(4.5rem+env(safe-area-inset-top))] z-[95] mx-auto w-fit">
          <button
            onClick={handleUndoDelete}
            aria-label="撤销删除"
            className="flex items-center gap-1.5 rounded-full border border-[#D4A432]/30 glass-surface px-5 py-2.5 text-sm font-bold text-[#D4A432] shadow-2xl transition-colors hover:bg-white/10 active:scale-95"
          >
            <Undo2 size={14} />
            撤销删除
          </button>
        </div>
      )}
      <AddToHomeScreenPrompt />
    </>
  );
}
