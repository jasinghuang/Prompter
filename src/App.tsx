import { useState, useEffect } from 'react';
import { ScriptList } from './components/ScriptList';
import { ScriptEditor } from './components/ScriptEditor';
import { Teleprompter } from './components/Teleprompter';
import { useScripts } from './store/useScripts';
import { useSettings } from './store/useSettings';
import { resolveIndexAfterEdit } from './lib/editResolve';

type View = 'list' | 'prompter' | 'editor';

export default function App() {
  const { scripts, addScript, updateScript, deleteScript } = useScripts();
  const { settings, updateSettings } = useSettings();

  const [view, setView] = useState<View>('list');
  const [activeId, setActiveId] = useState<string | null>(null);
  // 提词器当前阅读位置（受控，供编辑返回定位使用）
  const [prompterIndex, setPrompterIndex] = useState(0);
  // 从提词器进入编辑时的快照
  const [editSnapshot, setEditSnapshot] = useState<{ content: string; index: number } | null>(null);
  const [resetNotice, setResetNotice] = useState(false);

  const active = scripts.find((s) => s.id === activeId) ?? null;

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
    setPrompterIndex(0);
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

  if (view === 'prompter' && active) {
    return (
      <>
        <Teleprompter
          script={active}
          settings={settings}
          index={prompterIndex}
          onIndexChange={setPrompterIndex}
          onChangeSettings={updateSettings}
          onBack={() => setView('list')}
          onEdit={openEditorFromPrompter}
        />
        {resetNotice && (
          <div className="fixed left-1/2 top-20 z-[120] -translate-x-1/2 rounded-full bg-black/85 px-4 py-2 text-xs text-yellow-400 backdrop-blur">
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
        onSave={(id, title, content) => {
          updateScript(id, title, content);
          // 从提词器进入编辑的情形：判断返回后定位
          if (editSnapshot) {
            const newIndex = resolveIndexAfterEdit(editSnapshot.content, content, editSnapshot.index);
            if (newIndex === 0 && editSnapshot.index !== 0) {
              setResetNotice(true);
              setTimeout(() => setResetNotice(false), 3000);
            }
            setPrompterIndex(newIndex);
            setEditSnapshot({ content, index: newIndex });
          }
        }}
        onBack={() => setView(editSnapshot ? 'prompter' : 'list')}
      />
    );
  }

  return (
    <ScriptList
      scripts={scripts}
      onOpen={openPrompter}
      onEdit={(id) => { setActiveId(id); setEditSnapshot(null); setView('editor'); }}
      onDelete={deleteScript}
      onCreate={handleCreate}
    />
  );
}
