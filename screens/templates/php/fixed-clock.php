<?php

// fixed-clock.php: server-side fixed clock for /screens (repo CLAUDE.md
// "Isolation and lifecycle", "Server-side fixed clock", added after stage
// (b) STOP 2: a dashboard's server-side `now()` aggregates drifted between
// two capture runs because the Playwright clock only fakes the browser).
//
// Instantiated verbatim into `<project>/.screens/web/fixed-clock.php` by
// the Phase 2 scaffold executor (no project source file changes). Loaded
// via `auto_prepend_file` (screens/templates/php/zz-screens.ini),
// activated only through `PHP_INI_SCAN_DIR` (screens.mjs's
// `phpFixedClockEnv`, applied to both the serve and the seed/migrate
// commands), never the project's own php.ini scan dir -- a normal dev
// request through the same PHP install is unaffected.
//
// Inert unless SCREENS_FIXED_NOW is set, so this file is safe to leave in
// place between /screens runs.
$fixedNow = getenv('SCREENS_FIXED_NOW');
if ($fixedNow !== false && $fixedNow !== '') {
    require_once __DIR__.'/../../vendor/autoload.php';
    \Carbon\Carbon::setTestNow($fixedNow);
}
