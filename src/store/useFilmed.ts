import { useCallback, useEffect, useState } from 'react';

const FILMED_KEY = 'prompter_filmed';

function loadFilmed(): Set<string> {
  try {
    const raw = localStorage.getItem(FILMED_KEY);
    if (!raw) return new Set();
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(parsed);
  } catch {
    return new Set();
  }
}

export function useFilmed() {
  const [filmedIds, setFilmedIds] = useState<Set<string>>(() => loadFilmed());

  // 集中持久化：与 useScripts/useSettings 一致，避免在 setState updater 内做副作用
  useEffect(() => {
    try {
      localStorage.setItem(FILMED_KEY, JSON.stringify([...filmedIds]));
    } catch {
      /* noop */
    }
  }, [filmedIds]);

  const markFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      if (prev.has(id)) return prev;
      const next = new Set(prev);
      next.add(id);
      return next;
    });
  }, []);

  const toggleFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const clearStale = useCallback((validIds: string[]) => {
    const valid = new Set(validIds);
    setFilmedIds((prev) => {
      let changed = false;
      const next = new Set<string>();
      for (const id of prev) {
        if (valid.has(id)) next.add(id);
        else changed = true;
      }
      return changed ? next : prev;
    });
  }, []);

  const isFilmed = useCallback((id: string) => filmedIds.has(id), [filmedIds]);

  return { filmedIds, isFilmed, markFilmed, toggleFilmed, clearStale };
}
