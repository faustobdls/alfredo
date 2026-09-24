// Wraps src/client.js and src/alfredo.css into the DSH ModuleLoader factory format -> lib/client.js.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const source = readFileSync(new URL('./src/client.js', import.meta.url), 'utf8')
  .replace("import React from 'react';", "const React = require('react');")
  .replace("import { createRoot } from 'react-dom/client';", "const { createRoot } = require('react-dom/client');")
  .replace('export function apply(', 'function apply(')
  .replace('export default { apply };', '');
const css = JSON.stringify(readFileSync(new URL('./src/alfredo.css', import.meta.url), 'utf8'));

const out = `window.__ModuleLoader__.load({ id: 'alfredo-plugin', factory: (require) => {
var module = { exports: {} };
var exports = module.exports;
${source}
const CSS = ${css};
const applyWithStyle = (ctx) => {
  const style = document.createElement('style');
  style.setAttribute('data-alfredo', '');
  style.textContent = CSS;
  document.head.appendChild(style);
  ctx.effect(() => () => style.remove());
  return apply(ctx);
};
exports.apply = applyWithStyle;
exports.inject = ['slots'];
return module.exports;
} });
`;
mkdirSync(new URL('./lib/', import.meta.url), { recursive: true });
writeFileSync(new URL('./lib/client.js', import.meta.url), out);
