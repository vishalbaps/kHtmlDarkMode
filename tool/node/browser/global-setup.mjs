// Renders every fixture through the real KHtmlDarkMode.convert before the
// suite runs, so the browser always tests the current Dart output.
import { execFileSync } from 'node:child_process';

import { packageRoot } from '../engine.mjs';

export default function globalSetup() {
  execFileSync('dart', ['run', 'tool/render_fixtures.dart'], { cwd: packageRoot, stdio: 'inherit' });
}
