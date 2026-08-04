import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useFilmed } from './useFilmed';

beforeEach(() => localStorage.clear());

describe('useFilmed', () => {
  it('初始为空', () => {
    const { result } = renderHook(() => useFilmed());
    expect(result.current.filmedIds.size).toBe(0);
    expect(result.current.isFilmed('x')).toBe(false);
  });

  it('向后兼容：读取已有 prompter_filmed', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['a', 'b']));
    const { result } = renderHook(() => useFilmed());
    expect(result.current.isFilmed('a')).toBe(true);
    expect(result.current.isFilmed('b')).toBe(true);
  });

  it('markFilmed 只增并持久化', () => {
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.markFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(true);
    act(() => result.current.markFilmed('a')); // 幂等
    expect(result.current.filmedIds.size).toBe(1);
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual(['a']);
  });

  it('toggleFilmed 切换', () => {
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.toggleFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(true);
    act(() => result.current.toggleFilmed('a'));
    expect(result.current.isFilmed('a')).toBe(false);
  });

  it('clearStale 移除无效 id 并持久化', () => {
    localStorage.setItem('prompter_filmed', JSON.stringify(['a', 'b', 'c']));
    const { result } = renderHook(() => useFilmed());
    act(() => result.current.clearStale(['a', 'c'])); // b 已被删除
    expect(result.current.isFilmed('a')).toBe(true);
    expect(result.current.isFilmed('b')).toBe(false);
    expect(result.current.isFilmed('c')).toBe(true);
    expect(JSON.parse(localStorage.getItem('prompter_filmed')!)).toEqual(['a', 'c']);
  });
});
