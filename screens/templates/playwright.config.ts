// playwright.config.ts: run-local output for /screens' web driver
// (screens/references/platform-web.md "Invocation").
//
// Copied verbatim into `<project>/.screens/web/playwright.config.ts` by the
// Phase 2 scaffold executor, next to capture.spec.ts. Passed explicitly via
// `--config .screens/web/playwright.config.ts` (never auto-discovered: a
// project root's own playwright.config.* wins auto-discovery otherwise,
// which is not this file's job to override). Keeps captured PNGs' sibling
// output -- traces, videos, the run's outputDir -- inside `.screens/.run/`
// (already gitignored, `screens.mjs`'s `ensureGitignoreEntry`), so no
// `test-results/`/`playwright-report/` ever appear in the project root.
// `reporter: 'list'` is explicit for the same reason: the default local
// reporter also writes an HTML report unless told not to.
import { defineConfig } from '@playwright/test';

export default defineConfig({
  outputDir: '.screens/.run/playwright',
  reporter: 'list',
});
