import React from 'react';
import { createRoot } from 'react-dom/client';
import App from './App';
import { registerSW } from './sw/registerSW';
import './index.css';

if (import.meta.env.PROD) {
  registerSW('/Prompter/sw.js');
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
