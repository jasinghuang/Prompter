import { useCallback, useEffect, useState } from 'react';
import { TeleprompterSettings } from '../types';
import { loadSettings, saveSettings } from './storage';

export function useSettings() {
  const [settings, setSettings] = useState<TeleprompterSettings>(() => loadSettings());

  useEffect(() => {
    saveSettings(settings);
  }, [settings]);

  const updateSettings = useCallback((patch: Partial<TeleprompterSettings>) => {
    setSettings((prev) => ({ ...prev, ...patch }));
  }, []);

  return { settings, updateSettings };
}
