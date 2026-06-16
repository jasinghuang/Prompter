import { describe, it, expect } from 'vitest';
import {
  SPEED_PRESETS,
  SPEED_MIN,
  SPEED_MAX,
  msPerChar,
  estimateDurationSeconds,
  stepAutoAdvance,
} from './speed';

describe('speed 常量', () => {
  it('包含 4 个预设档', () => {
    expect(SPEED_PRESETS.map((p) => p.wpn)).toEqual([80, 160, 240, 320]);
  });
  it('范围 60–360', () => {
    expect(SPEED_MIN).toBe(60);
    expect(SPEED_MAX).toBe(360);
  });
});

describe('msPerChar', () => {
  it('160 WPN → 60000/160 = 375ms', () => {
    expect(msPerChar(160)).toBe(375);
  });
  it('80 WPN → 750ms', () => {
    expect(msPerChar(80)).toBe(750);
  });
  it('非正数返回 Infinity', () => {
    expect(msPerChar(0)).toBe(Infinity);
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

describe('stepAutoAdvance', () => {
  it('未到每字阈值时不推进，累加 dt', () => {
    // 160 WPN → 375ms/字
    expect(stepAutoAdvance(100, 200, 160)).toEqual({ accumulator: 300, advance: 0 });
  });
  it('累积超过阈值时推进整数字数并保留余数', () => {
    // 累积 400, dt 50 → 450; 450/375 = 1 余 75
    expect(stepAutoAdvance(400, 50, 160)).toEqual({ accumulator: 75, advance: 1 });
  });
  it('可一次推进多字', () => {
    // 累积 0, dt 800 → 800; 800/375 = 2 余 50
    expect(stepAutoAdvance(0, 800, 160)).toEqual({ accumulator: 50, advance: 2 });
  });
});
