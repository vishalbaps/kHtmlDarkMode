// The browser suite. Chromium stands in for Android's WebView and WebKit for
// iOS's WKWebView: the in-page pass runs in both engines on every run.
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './browser',
  globalSetup: './browser/global-setup.mjs',
  fullyParallel: true,
  reporter: [['list']],
  use: {
    viewport: { width: 360, height: 740 },
    deviceScaleFactor: 1,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 360, height: 740 } } },
    { name: 'webkit', use: { ...devices['Desktop Safari'], viewport: { width: 360, height: 740 } } },
  ],
});
