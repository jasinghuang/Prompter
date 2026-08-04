import { useCallback, useState } from 'react';

const FILMED_KEY = 'prompter_filmed';

function loadFilmed(): Set<string> {
  try {
    const raw = localStorage.getItem(FILMED_KEY);
    return new Set(raw ? JSON.parse(raw) : []);
  } catch {
    return new Set();
  }
}

export function useFilmed() {
  const [filmedIds, setFilmedIds] = useState<Set<string>>(() => loadFilmed());

  const persist = (next: Set<string>) => {
    try {
      localStorage.setItem(FILMED_KEY, JSON.stringify([...next]));
    } catch {
      /* noop */
    }
  };

  const markFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      if (prev.has(id)) return prev;
      const next = new Set(prev);
      next.add(id);
      persist(next);
      return next;
    });
  }, []);

  const toggleFilmed = useCallback((id: string) => {
    setFilmedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      persist(next);
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
      if (!changed) return prev;
      persist(next);
      return next;
    });
  }, []);

  const isFilmed = useCallback((id: string) => filmedIds.has(id), [filmedIds]);

  return { filmedIds, isFilmed, markFilmed, toggleFilmed, clearStale };
}
