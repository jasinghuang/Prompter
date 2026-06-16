import { describe, it, expect } from 'vitest';
import { tokenize, countReadableChars } from './tokens';

describe('tokenize', () => {
  it('把字符串拆成带索引的 token 数组', () => {
    expect(tokenize('ab')).toEqual([
      { id: 0, char: 'a' },
      { id: 1, char: 'b' },
    ]);
  });

  it('保留换行符作为独立 token', () => {
    const tokens = tokenize('a\nb');
    expect(tokens).toHaveLength(3);
    expect(tokens[1]).toEqual({ id: 1, char: '\n' });
  });

  it('用码点拆分，正确处理中文（含 emoji 占多码点）', () => {
    expect(tokenize('你好')).toEqual([
      { id: 0, char: '你' },
      { id: 1, char: '好' },
    ]);
  });

  it('空字符串返回空数组', () => {
    expect(tokenize('')).toEqual([]);
  });
});

describe('countReadableChars', () => {
  it('统计非空白字符数', () => {
    expect(countReadableChars('你 好\n世界')).toBe(4);
  });

  it('空串为 0', () => {
    expect(countReadableChars('')).toBe(0);
  });
});
