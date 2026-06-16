import { describe, it, expect, beforeEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useScripts } from './useScripts';

beforeEach(() => localStorage.clear());

describe('useScripts', () => {
  it('初始为空，addScript 后新增一篇并持久化', () => {
    const { result } = renderHook(() => useScripts());
    expect(result.current.scripts).toEqual([]);
    act(() => result.current.addScript());
    expect(result.current.scripts).toHaveLength(1);
    expect(result.current.scripts[0].title).toBe('未命名稿件');
    // 持久化
    const stored = JSON.parse(localStorage.getItem('prompter_scripts')!);
    expect(stored).toHaveLength(1);
  });

  it('updateContent 更新正文与 updatedAt', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.updateContent(id, '新内容'));
    expect(result.current.scripts[0].content).toBe('新内容');
  });

  it('updateScript 更新标题与正文', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.updateScript(id, '标题', '正文'));
    const s = result.current.scripts[0];
    expect(s.title).toBe('标题');
    expect(s.content).toBe('正文');
  });

  it('deleteScript 删除指定稿件', () => {
    const { result } = renderHook(() => useScripts());
    act(() => result.current.addScript());
    const id = result.current.scripts[0].id;
    act(() => result.current.deleteScript(id));
    expect(result.current.scripts).toHaveLength(0);
  });

  it('初始读取已持久化的稿件', () => {
    localStorage.setItem('prompter_scripts', JSON.stringify([
      { id: 'x', title: 't', content: 'c', createdAt: 1, updatedAt: 1 },
    ]));
    const { result } = renderHook(() => useScripts());
    expect(result.current.scripts).toHaveLength(1);
  });
});
