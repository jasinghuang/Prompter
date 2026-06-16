import { describe, it, expect, beforeEach } from 'vitest';
import { loadScripts, saveScripts, loadSettings, saveSettings, SCRIPTS_KEY, SETTINGS_KEY } from './storage';
import { DEFAULT_SETTINGS } from '../types';

beforeEach(() => localStorage.clear());

describe('scripts 存储', () => {
  it('无数据时返回空数组', () => {
    expect(loadScripts()).toEqual([]);
  });

  it('保存后可读回', () => {
    const data = [{ id: '1', title: 't', content: 'c', createdAt: 1, updatedAt: 1 }];
    saveScripts(data);
    expect(loadScripts()).toEqual(data);
  });

  it('JSON 损坏时回退空数组', () => {
    localStorage.setItem(SCRIPTS_KEY, '{not json');
    expect(loadScripts()).toEqual([]);
  });

  it('解析为非数组时回退空数组', () => {
    localStorage.setItem(SCRIPTS_KEY, '{"a":1}');
    expect(loadScripts()).toEqual([]);
  });
});

describe('settings 存储', () => {
  it('无数据时返回默认设置', () => {
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS);
  });

  it('保存后读回并合并默认值（缺字段补默认）', () => {
    saveSettings({ ...DEFAULT_SETTINGS, fontSize: 100 });
    const loaded = loadSettings();
    expect(loaded.fontSize).toBe(100);
    expect(loaded.scrollSpeed).toBe(DEFAULT_SETTINGS.scrollSpeed);
  });

  it('JSON 损坏时回退默认设置', () => {
    localStorage.setItem(SETTINGS_KEY, 'broken');
    expect(loadSettings()).toEqual(DEFAULT_SETTINGS);
  });
});
