import { useCallback, useEffect, useState } from 'react';
import { Script } from '../types';
import { loadScripts, saveScripts } from './storage';

export function useScripts() {
  const [scripts, setScripts] = useState<Script[]>(() => loadScripts());

  useEffect(() => {
    saveScripts(scripts);
  }, [scripts]);

  const addScript = useCallback(() => {
    const now = Date.now();
    const newScript: Script = {
      id: crypto.randomUUID(),
      title: '未命名稿件',
      content: '',
      createdAt: now,
      updatedAt: now,
    };
    setScripts((prev) => [newScript, ...prev]);
    return newScript.id;
  }, []);

  const updateContent = useCallback((id: string, content: string) => {
    setScripts((prev) =>
      prev.map((s) => (s.id === id ? { ...s, content, updatedAt: Date.now() } : s))
    );
  }, []);

  const updateScript = useCallback((id: string, title: string, content: string) => {
    setScripts((prev) =>
      prev.map((s) => (s.id === id ? { ...s, title, content, updatedAt: Date.now() } : s))
    );
  }, []);

  const deleteScript = useCallback((id: string) => {
    setScripts((prev) => prev.filter((s) => s.id !== id));
  }, []);

  /** 星标/取消星标（纯元数据变更，不更新 updatedAt） */
  const toggleStar = useCallback((id: string) => {
    setScripts((prev) => prev.map((s) => (s.id === id ? { ...s, starred: !s.starred } : s)));
  }, []);

  /** 移动到文件夹；folder 为 null 时移出到未分组 */
  const moveToFolder = useCallback((id: string, folder: string | null) => {
    setScripts((prev) => prev.map((s) => (s.id === id ? { ...s, folder: folder ?? undefined } : s)));
  }, []);

  /** 撤销删除：把快照稿件插回原位置（index 越界时插到末尾） */
  const restoreScript = useCallback((script: Script, index: number) => {
    setScripts((prev) => {
      const next = [...prev];
      next.splice(Math.min(Math.max(index, 0), next.length), 0, script);
      return next;
    });
  }, []);

  const clearAll = useCallback(() => {
    setScripts([]);
  }, []);

  const importScript = useCallback((title: string, content: string, folder?: string) => {
    const now = Date.now();
    const s: Script = {
      id: crypto.randomUUID(),
      title: title || '导入的稿件',
      content,
      createdAt: now,
      updatedAt: now,
      ...(folder ? { folder } : null),
    };
    setScripts((prev) => [s, ...prev]);
    return s.id;
  }, []);

  return { scripts, addScript, updateContent, updateScript, deleteScript, restoreScript, toggleStar, moveToFolder, clearAll, importScript };
}
