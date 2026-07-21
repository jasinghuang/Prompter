export interface Script {
  id: string;
  title: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export type ScrollMode = 'manual' | 'auto';

export type TextAlign = 'left' | 'center' | 'right';

export interface TeleprompterSettings {
  fontSize: number;
  letterSpacing: number;
  lineHeight: number;
  scrollSpeed: number;
  mirror: boolean;
  /** 阅读区左右内边距（百分比），默认 8 */
  horizontalPadding: number;
  /** 文本对齐，默认 left */
  textAlign: TextAlign;
  /** 自动暂停关键词（空字符串 = 不启用），默认 '' */
  pauseKeyword: string;
}

export const DEFAULT_SETTINGS: TeleprompterSettings = {
  fontSize: 64,
  letterSpacing: 0.05,
  lineHeight: 1.6,
  scrollSpeed: 160,
  mirror: false,
  horizontalPadding: 8,
  textAlign: 'left',
  pauseKeyword: '',
};

export const FONT_SIZE_MIN = 24;
export const FONT_SIZE_MAX = 120;
export const LETTER_SPACING_MIN = 0;
export const LETTER_SPACING_MAX = 0.3;
export const LINE_HEIGHT_MIN = 1.0;
export const LINE_HEIGHT_MAX = 2.5;
export const PADDING_MIN = 4;
export const PADDING_MAX = 20;
