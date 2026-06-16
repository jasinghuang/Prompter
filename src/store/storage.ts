import { Script, TeleprompterSettings, DEFAULT_SETTINGS } from '../types';

export const SCRIPTS_KEY = 'prompter_scripts';
export const SETTINGS_KEY = 'prompter_settings';

export function loadScripts(): Script[] {
  try {
    const raw = localStorage.getItem(SCRIPTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as Script[]) : [];
  } catch {
    return [];
  }
}

export function saveScripts(scripts: Script[]): void {
  localStorage.setItem(SCRIPTS_KEY, JSON.stringify(scripts));
}

export function loadSettings(): TeleprompterSettings {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    const parsed = JSON.parse(raw);
    return { ...DEFAULT_SETTINGS, ...(parsed as Partial<TeleprompterSettings>) };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(settings: TeleprompterSettings): void {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}
