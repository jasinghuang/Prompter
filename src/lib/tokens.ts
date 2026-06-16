export interface Token {
  id: number;
  char: string;
}

/** 用 Array.from 按码点拆分，正确处理中文与多码点字符。 */
export function tokenize(content: string): Token[] {
  return Array.from(content).map((char, index) => ({ id: index, char }));
}

/** 非空白字符数，用于预估总时长（排除空格/换行）。 */
export function countReadableChars(content: string): number {
  return Array.from(content).filter((c) => c.trim().length > 0).length;
}
