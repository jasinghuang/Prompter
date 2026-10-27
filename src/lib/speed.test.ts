import { describe, it, expect } from 'vitest';
import { SPEED_MIN, SPEED_MAX, estimateDurationSeconds } from './speed';

describe('speed 常量', () => {
  it('范围 100–700', () => {
    expect(SPEED_MIN).toBe(100);
    expect(SPEED_MAX).toBe(700);
  });
});

describe('estimateDurationSeconds', () => {
  it('总时长 = 字数 / WPN * 60', () => {
    // 1600 字 @ 160 WPN → 10 分钟 = 600 秒
    expect(estimateDurationSeconds(1600, 160)).toBe(600);
  });
  it('字数为 0 → 0', () => {
    expect(estimateDurationSeconds(0, 160)).toBe(0);
  });
  it('WPN 为 0 → 0', () => {
    expect(estimateDurationSeconds(100, 0)).toBe(0);
  });
});
