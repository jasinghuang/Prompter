import { describe, it, expect } from 'vitest';
import { resolveIndexAfterEdit } from './editResolve';

describe('resolveIndexAfterEdit', () => {
  it('内容在当前位置之前未改 → 保持原位置', () => {
    // old: "abcde", index 3; new: "abcXY" → 前 3 字符 "abc" 一致 → 保持 3
    expect(resolveIndexAfterEdit('abcde', 'abcXY', 3)).toBe(3);
  });

  it('内容在当前位置之前有改动 → 重置 0', () => {
    // old: "abcde", index 3; new: "aXcde" → 前 3 字符 "aXc" != "abc" → 0
    expect(resolveIndexAfterEdit('abcde', 'aXcde', 3)).toBe(0);
  });

  it('新内容短于当前位置 → 重置 0', () => {
    expect(resolveIndexAfterEdit('abcde', 'ab', 3)).toBe(0);
  });

  it('index 为 0 → 总是 0', () => {
    expect(resolveIndexAfterEdit('abcde', 'XYZ', 0)).toBe(0);
  });
});
