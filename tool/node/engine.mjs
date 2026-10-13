// Loads the SHIPPED script — js/k_html_dark_mode.js, the file the Dart package
// embeds — and returns its pure colour functions, without a DOM.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const source = readFileSync(join(packageRoot, 'js', 'k_html_dark_mode.js'), 'utf8');

/** `#RRGGBB` to the [r, g, b] in 0..1 the script works in. */
export function rgb(hex) {
  const h = hex.replace('#', '');
  return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
}

/** The script's pure API for a configuration and page background. */
export function loadEngine(config, pageHex) {
  // eslint-disable-next-line no-new-func
  const kdmDarkMode = new Function(`${source}\nreturn kdmDarkMode;`)();
  return kdmDarkMode({ config, page: rgb(pageHex), isDark: true, exportsOnly: true });
}

export function readVectors() {
  return JSON.parse(readFileSync(join(packageRoot, 'test', 'golden', 'vectors.json'), 'utf8'));
}
