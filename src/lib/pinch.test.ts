import { describe, it, expect } from 'vitest';
import { computePinchFontSize } from './pinch';

describe('computePinchFontSize', () => {
  it('双指张开按比例放大字号', () => {
    expect(computePinchFontSize(80, 40, 64)).toBe(120); // 64 × 2 = 128 → clamp 到 120
  });

  it('双指收拢按比例缩小字号', () => {
    expect(computePinchFontSize(20, 40, 64)).toBe(32);
  });

  it('比例不变时字号不变', () => {
    expect(computePinchFontSize(40, 40, 64)).toBe(64);
  });

  it('结果按步进 2 取偶', () => {
    expect(computePinchFontSize(61, 40, 64)).toBe(98); // 97.6 → 98
  });

  it('结果夹在字号上下限之间', () => {
    expect(computePinchFontSize(1000, 1, 64)).toBe(120);
    expect(computePinchFontSize(1, 1000, 64)).toBe(24);
  });

  it('初始间距为 0 时返回起始字号（防御除零）', () => {
    expect(computePinchFontSize(50, 0, 64)).toBe(64);
  });
});
