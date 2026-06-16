export interface Script {
  id: string;
  title: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export interface TeleprompterSettings {
  fontSize: number;
  letterSpacing: number;
  lineHeight: number;
  scrollSpeed: number;
  mirror: boolean;
}

export type ScrollMode = 'manual' | 'auto';

export const DEFAULT_SETTINGS: TeleprompterSettings = {
  fontSize: 64,
  letterSpacing: 0.05,
  lineHeight: 1.6,
  scrollSpeed: 160,
  mirror: false,
};

export const FONT_SIZE_MIN = 24;
export const FONT_SIZE_MAX = 120;
export const LETTER_SPACING_MIN = 0;
export const LETTER_SPACING_MAX = 0.3;
export const LINE_HEIGHT_MIN = 1.0;
export const LINE_HEIGHT_MAX = 2.5;
