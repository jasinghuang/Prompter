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

  const clearAll = useCallback(() => {
    setScripts([]);
  }, []);

  const importScript = useCallback((title: string, content: string) => {
    const now = Date.now();
    const s: Script = {
      id: crypto.randomUUID(),
      title: title || '导入的稿件',
      content,
      createdAt: now,
      updatedAt: now,
    };
    setScripts((prev) => [s, ...prev]);
    return s.id;
  }, []);

  return { scripts, addScript, updateContent, updateScript, deleteScript, clearAll, importScript };
}
