import { describe, it, expect } from 'vitest';
import { splitByParagraphs, splitByKeyword } from './split';

describe('splitByParagraphs', () => {
  it('按连续空行切分并去除首尾空白', () => {
    const content = '第一段标题\n第一段内容\n\n第二段标题\n第二段内容';
    expect(splitByParagraphs(content)).toEqual(['第一段标题\n第一段内容', '第二段标题\n第二段内容']);
  });

  it('三段及以上空行视为一个分隔', () => {
    expect(splitByParagraphs('甲\n\n\n\n乙')).toEqual(['甲', '乙']);
  });

  it('过滤开头/结尾/纯空白的空段', () => {
    expect(splitByParagraphs('\n\n   \n甲\n\n乙\n\n')).toEqual(['甲', '乙']);
  });

  it('没有空行时返回单段', () => {
    expect(splitByParagraphs('甲\n乙')).toEqual(['甲\n乙']);
  });
});

describe('splitByKeyword', () => {
  it('在每个关键词出现处之前切分，新段以关键词开头', () => {
    const content = '开场白\n主持人：大家好\n\n嘉宾：你好\n主持人：再见';
    expect(splitByKeyword(content, '主持人：')).toEqual([
      '开场白',
      '主持人：大家好\n\n嘉宾：你好',
      '主持人：再见',
    ]);
  });

  it('关键词出现在开头时首段为空，应被过滤', () => {
    expect(splitByKeyword('主持人：大家好\n\n主持人：再见', '主持人：')).toEqual([
      '主持人：大家好',
      '主持人：再见',
    ]);
  });

  it('关键词连续出现不产生空段', () => {
    expect(splitByKeyword('甲主持人：主持人：乙', '主持人：')).toEqual(['甲', '主持人：', '主持人：乙']);
  });

  it('关键词未出现时返回整段', () => {
    expect(splitByKeyword('没有标记的文字', '主持人：')).toEqual(['没有标记的文字']);
  });

  it('空关键词返回空数组', () => {
    expect(splitByKeyword('任何内容', '')).toEqual([]);
  });

  it('关键词含正则特殊字符时按字面量匹配', () => {
    expect(splitByKeyword('甲.*乙', '.*')).toEqual(['甲', '.*乙']);
  });

  it('切分出的段保留内部单换行', () => {
    expect(splitByKeyword('第一行\n第二行\n主持人：第三行', '主持人：')).toEqual([
      '第一行\n第二行',
      '主持人：第三行',
    ]);
  });
});
