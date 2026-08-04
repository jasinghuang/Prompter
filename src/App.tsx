import { useState, useEffect } from 'react';
import { useTransientFlag } from './hooks/useTransientFlag';
import { ScriptList } from './components/ScriptList';
import { ScriptEditor } from './components/ScriptEditor';
import { Teleprompter } from './components/Teleprompter';
import { AddToHomeScreenPrompt } from './components/AddToHomeScreenPrompt';
import { useScripts } from './store/useScripts';
import { useSettings } from './store/useSettings';
import { useFilmed } from './store/useFilmed';
import { resolveIndexAfterEdit } from './lib/editResolve';

type View = 'list' | 'prompter' | 'editor';

const POS_KEY = 'prompter_pos_';

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
  const { scripts, addScript, updateScript, deleteScript, clearAll, importScript } = useScripts();
  const { settings, updateSettings } = useSettings();
  const { filmedIds, toggleFilmed, clearStale } = useFilmed();

  const [view, setView] = useState<View>('list');
  const [activeId, setActiveId] = useState<string | null>(null);
  // 提词器当前阅读位置（受控，供编辑返回定位使用）
  const [prompterIndex, setPrompterIndex] = useState(0);
  // 从提词器进入编辑时的快照
  const [editSnapshot, setEditSnapshot] = useState<{ content: string; index: number } | null>(null);
  const [resetNotice, showResetNotice] = useTransientFlag(3000);

  const active = scripts.find((s) => s.id === activeId) ?? null;

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

  const handleSplit = () => {
    if (!active) return;
    const paragraphs = active.content.split(/\n{2,}/).filter((p) => p.trim() !== '');
    if (paragraphs.length < 2) return;
    for (const para of paragraphs) {
      const lines = para.trim().split('\n');
      const title = lines[0].trim();
      importScript(title, para.trim());
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
        />
        {resetNotice && (
          <div className="fixed left-1/2 top-20 z-[120] -translate-x-1/2 rounded-full border border-[#D4A432]/20 bg-white/10 backdrop-blur-xl px-4 py-2.5 text-xs text-[#D4A432] backdrop-blur-xl shadow-2xl">
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
        pauseKeyword={settings.pauseKeyword}
        onPauseKeywordChange={(kw) => updateSettings({ pauseKeyword: kw })}
        pauseOnParagraph={settings.pauseOnParagraph}
        onPauseOnParagraphChange={(v) => updateSettings({ pauseOnParagraph: v })}
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
        onOpen={openPrompter}
        onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
        onDelete={deleteScript}
        onCreate={handleCreate}
        onToggleFilmed={toggleFilmed}
        onDeleteAll={clearAll}
      />
      <AddToHomeScreenPrompt />
    </>
  );
}
