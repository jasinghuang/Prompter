import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { registerSW } from './sw/registerSW';
import { detectStandalone, detectIOS, shouldUseSolidGlass } from './lib/pwa';
import './index.css';

if (import.meta.env.PROD) {
  registerSW('/Prompter/sw.js');
}

// iOS PWA 花屏规避：首帧渲染前挂上 glass-solid，避免先渲染毛玻璃再闪变
if (shouldUseSolidGlass({ isIOS: detectIOS(), standalone: detectStandalone() })) {
  document.documentElement.classList.add('glass-solid');
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
