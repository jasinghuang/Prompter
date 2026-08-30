import '@testing-library/jest-dom/vitest';
import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';

// jsdom 在较新 Node 版本下可能未把 localStorage 挂到全局，这里兜底
if (typeof globalThis.localStorage === 'undefined') {
  const store = new Map<string, string>();
  globalThis.localStorage = {
    getItem: (k: string) => store.get(k) ?? null,
    setItem: (k: string, v: string) => store.set(k, String(v)),
    removeItem: (k: string) => store.delete(k),
    clear: () => store.clear(),
    key: (i: number) => [...store.keys()][i] ?? null,
    get length() {
      return store.size;
    },
  } as Storage;
}

// jsdom 无 PointerEvent：polyfill（继承 MouseEvent 以携带 clientX/Y，并保留 pointerId）
if (typeof window !== 'undefined' && typeof window.PointerEvent === 'undefined') {
  class PointerEventPolyfill extends MouseEvent {
    pointerId: number;
    pointerType: string;
    isPrimary: boolean;
    constructor(type: string, init: PointerEventInit = {}) {
      super(type, init);
      this.pointerId = init.pointerId ?? 0;
      this.pointerType = init.pointerType ?? '';
      this.isPrimary = init.isPrimary ?? false;
    }
  }
  window.PointerEvent = PointerEventPolyfill as unknown as typeof PointerEvent;
}

// jsdom 无 Touch/TouchEvent：polyfill（携带 touches/changedTouches 触摸点列表）
if (typeof window !== 'undefined' && typeof window.TouchEvent === 'undefined') {
  class TouchPolyfill {
    identifier: number;
    clientX: number;
    clientY: number;
    target: EventTarget | null;
    constructor(init: { identifier: number; clientX: number; clientY: number; target?: EventTarget }) {
      this.identifier = init.identifier;
      this.clientX = init.clientX;
      this.clientY = init.clientY;
      this.target = init.target ?? null;
    }
  }
  class TouchEventPolyfill extends Event {
    touches: TouchPolyfill[];
    changedTouches: TouchPolyfill[];
    constructor(type: string, init: EventInit & { touches?: TouchPolyfill[]; changedTouches?: TouchPolyfill[] } = {}) {
      super(type, { bubbles: true, cancelable: true, ...init });
      this.touches = init.touches ?? [];
      this.changedTouches = init.changedTouches ?? init.touches ?? [];
    }
  }
  window.TouchEvent = TouchEventPolyfill as unknown as typeof TouchEvent;
  window.Touch = TouchPolyfill as unknown as typeof Touch;
}

afterEach(() => {
  cleanup();
  localStorage.clear();
});
