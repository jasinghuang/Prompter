import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useSettings } from './useSettings';
import { DEFAULT_SETTINGS } from '../types';

beforeEach(() => localStorage.clear());

describe('useSettings', () => {
  it('初始为默认设置', () => {
    const { result } = renderHook(() => useSettings());
    expect(result.current.settings).toEqual(DEFAULT_SETTINGS);
  });

  it('updateSettings 合并并持久化', () => {
    const { result } = renderHook(() => useSettings());
    act(() => result.current.updateSettings({ fontSize: 100 }));
    expect(result.current.settings.fontSize).toBe(100);
    const stored = JSON.parse(localStorage.getItem('prompter_settings')!);
    expect(stored.fontSize).toBe(100);
  });
});
