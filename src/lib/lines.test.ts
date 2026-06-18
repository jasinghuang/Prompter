import { describe, it, expect } from 'vitest';
import { computeLineIndices } from './lines';

describe('computeLineIndices', () => {
  it('相同 top 归同行，不同 top 递增行号', () => {
    // 3 字在第一行(top 0)，2 字在第二行(top 60)，1 字在第三行(top 120)
    expect(computeLineIndices([0, 0, 0, 60, 60, 120])).toEqual([0, 0, 0, 1, 1, 2]);
  });

  it('全部相同 → 全为行 0', () => {
    expect(computeLineIndices([0, 0, 0])).toEqual([0, 0, 0]);
  });

  it('容差 1px 内视为同行（亚像素）', () => {
    expect(computeLineIndices([0, 0.5, 60])).toEqual([0, 0, 1]);
  });

  it('空数组 → 空数组', () => {
    expect(computeLineIndices([])).toEqual([]);
  });

  it('乱序出现的相同 top 仍归同已建立行号', () => {
    // top 0, 60, 0 → 第三个回到行 0
    expect(computeLineIndices([0, 60, 0])).toEqual([0, 1, 0]);
  });
});
