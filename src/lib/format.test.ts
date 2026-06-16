import { describe, it, expect } from 'vitest';
import { formatTime } from './format';

describe('formatTime', () => {
  it('0 秒 → 00:00', () => {
    expect(formatTime(0)).toBe('00:00');
  });
  it('32 秒 → 00:32', () => {
    expect(formatTime(32)).toBe('00:32');
  });
  it('135 秒 → 02:15', () => {
    expect(formatTime(135)).toBe('02:15');
  });
  it('取整（向下）', () => {
    expect(formatTime(32.9)).toBe('00:32');
  });
  it('负数当作 0', () => {
    expect(formatTime(-5)).toBe('00:00');
  });
});
