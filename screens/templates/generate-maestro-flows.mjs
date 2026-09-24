#!/usr/bin/env node
//
// generate-maestro-flows.mjs: instantiated verbatim into
// `<project>/.screens/android/generate-maestro-flows.mjs` by the Phase 2
// scaffold, alongside `.screens/android/maestro-flow.yaml` (also copied
// verbatim from `screens/templates/maestro-flow.yaml`). Reads
// `.screens/config.json` and `.screens/manifest.json` from `process.cwd()`
// at generation time (repo CLAUDE.md "Reviewer": manifest read at runtime,
// never hard-coded), so the same file works unmodified for every
// Android/Capacitor pilot.
//
// Contract: one CLI arg, a comma-separated list of stale entry ids (from
// `screens.mjs plan`'s `PLAN_ENTRY <id> {new|stale|missing_png}` lines,
// skip `unchanged`; empty/absent arg means every android/capacitor entry).
// Writes one instantiated flow YAML per (entry, state, role) into
// `.screens/.maestro-generated/` (ephemeral, cleared and recreated on every
// call, never committed -- the generated-output relationship to
// `maestro-flow.yaml` mirrors `.screens/.incoming/<platform>/` for PNGs).
// Prints one `FLOW <path>` line per generated file and a final
// `GENERATE_RESULT=OK count=<n>` line, exit 0. The driver invocation loop
// (platform-maestro.md "Explicit-intent navigation") MUST run the printed
// `FLOW` lines in the order printed, not glob a directory: `clearState`
// (true only for the first flow of a given role, see `roleSeen` below) is
// assigned in this same iteration order, so running out of order would
// clear state mid-role and drop the login session unexpectedly.

import { readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.cwd();

// `${PROJECT_ROOT}` placeholder (config-schema.md), own equivalent of
// screens.mjs's `expandProjectRoot` since this file runs outside that
// module; an unknown `${X}` placeholder is left untouched.
function expandProjectRoot(value, root) {
  if (typeof value === 'string') return value.replaceAll('${PROJECT_ROOT}', root);
  if (Array.isArray(value)) return value.map((v) => expandProjectRoot(v, root));
  if (value && typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = expandProjectRoot(v, root);
    return out;
  }
  return value;
}

const config = expandProjectRoot(JSON.parse(readFileSync(join(ROOT, '.screens/config.json'), 'utf8')), ROOT);
const manifest = expandProjectRoot(JSON.parse(readFileSync(join(ROOT, '.screens/manifest.json'), 'utf8')), ROOT);
const template = readFileSync(join(ROOT, '.screens/android/maestro-flow.yaml'), 'utf8');

// Per-machine demo password (security fix: no demo password in any repo,
// including a generated flow YAML): only the emails come from config.json,
// the password itself is never read here -- the generated flow embeds the
// literal string `${DEMO_PASSWORD}`, a Maestro env-var placeholder Maestro
// substitutes at `maestro test` time from `-e DEMO_PASSWORD=...`
// (platform-maestro.md "Invocation"), so the password never lands on disk.

const OUT_DIR = join(ROOT, '.screens/.maestro-generated');
rmSync(OUT_DIR, { recursive: true, force: true });
mkdirSync(OUT_DIR, { recursive: true });

const staleArg = process.argv[2] || '';
const staleIds = staleArg ? new Set(staleArg.split(',').filter(Boolean)) : null;
// Theme (3rd arg, default "light"): the generator is called once per
// themed pass (platform-maestro.md "Invocation"), so the embedded
// takeScreenshot name below must carry the theme that pass is actually
// capturing, not a fixed placeholder.
const theme = process.argv[3] || 'light';

const androidConfig = config.android || {};
const appId = androidConfig.app_id || (config.web && config.web.app_id) || 'com.example.app';
const loginSelectors = androidConfig.login_selectors
  || { email: 'email', password: 'password', submit: 'password' };
const deviceClass = androidConfig.device_class || 'android-phone';
const outgoingDir = join(ROOT, '.screens/.incoming/android');
mkdirSync(outgoingDir, { recursive: true });

// Maps the shared native `steps[]` vocabulary (tap_tab/tap/wait/type/
// swipe_up/swipe_down, config-schema.md, same shape the Apple driver reads)
// to Maestro flow commands.
function stepToMaestro(step) {
  const target = step.id ? { id: step.id } : { text: step.label };
  const optional = step.optional === 'true' || step.optional === true;
  switch (step.action) {
    case 'tap_tab':
    case 'tap':
      return optional
        ? `- tapOn:\n    ${target.id ? `id: "${target.id}"` : `text: "${target.label}"`}\n    optional: true`
        : `- tapOn:\n    ${target.id ? `id: "${target.id}"` : `text: "${target.label}"`}`;
    case 'wait':
      return `- extendedWaitUntil:\n    visible:\n      ${target.id ? `id: "${target.id}"` : `text: "${target.label}"`}\n    timeout: ${optional ? 2000 : 10000}`;
    case 'type':
      return `- inputText: "${step.text}"`;
    case 'swipe_up':
      return '- swipe:\n    direction: UP';
    case 'swipe_down':
      return '- swipe:\n    direction: DOWN';
    default:
      return `# unknown step action "${step.action}", skipped`;
  }
}

function loginStepsFor(role) {
  if (role === 'guest') return '';
  const emptyLogins = config.demo_logins_empty || {};
  const email = (emptyLogins[role]) || (config.demo_logins && config.demo_logins[role]);
  if (!email) return `# no demo login configured for role "${role}"`;
  const password = '${DEMO_PASSWORD}';
  return [
    `- tapOn:\n    id: "${loginSelectors.email}"`,
    `- inputText: "${email}"`,
    `- tapOn:\n    id: "${loginSelectors.password}"`,
    `- inputText: "${password}"`,
    `- tapOn:\n    id: "${loginSelectors.submit}"`,
  ].join('\n');
}

function errorFillSteps(entry) {
  const fields = entry.error_fill || [];
  if (!fields.length) return '';
  return fields.map((f) => `- tapOn:\n    id: "${f.selector}"\n- inputText: "${f.value}"`).join('\n')
    + `\n- tapOn:\n    id: "${loginSelectors.submit}"`;
}

let count = 0;
const lines = [];

// `clearState: true` (and therefore `{{LOGIN_STEPS}}`) fires only for the
// FIRST flow generated for a given role in this call (platform-maestro.md
// "Explicit-intent navigation"): a fresh app install once per role, not
// once per (entry, state, role), so a logged-in role's session survives
// across its own entries instead of re-logging in on every one.
const roleSeen = new Set();

for (const entry of manifest.entries || []) {
  if (entry.platform !== 'android' && entry.platform !== 'capacitor') continue;
  if (staleIds && !staleIds.has(entry.id)) continue;

  const states = entry.states && entry.states.length ? entry.states : ['filled'];
  const roles = entry.roles && entry.roles.length ? entry.roles : ['guest'];

  for (const state of states) {
    for (const role of roles) {
      const clearState = !roleSeen.has(role);
      roleSeen.add(role);

      // Navigation for an entry with a `reach` URL happens externally,
      // before this flow runs (`screens.mjs android-navigate`, see
      // platform-maestro.md "Explicit-intent navigation") -- `openLink`
      // resolved an implicit VIEW intent to Chrome instead of the app,
      // since the app's App Link intent-filter only verifies the
      // production host, never the isolated backend host `server.url`
      // points at (live STOP 2026-09-24). Falls back to the shared
      // steps[] tap vocabulary only when no `reach` URL exists.
      const reachSteps = entry.reach
        ? '# navigated externally via `screens.mjs android-navigate` before this flow runs'
        : (entry.steps || []).map(stepToMaestro).join('\n') || '# no steps[] or reach configured';
      const errorSteps = state === 'error' ? errorFillSteps(entry) : '';
      const filename = `${entry.id}__${state}__${role}__${deviceClass}__${theme}.png`;
      // Maestro's `takeScreenshot: <name>` writes `<name>.png` to the
      // CURRENT WORKING DIRECTORY, not an arbitrary path (verified against
      // the events pilot's own pre-existing `.gitignore` comment: "Maestro
      // takeScreenshot writes PNGs to the repo root on each run" + a
      // `/*.png` rule already there for exactly this) -- a bare name, never
      // `outgoingDir` joined in. The driver invocation
      // (platform-maestro.md "Invocation") moves the written PNGs from the
      // project root into `.screens/.incoming/android/` after `maestro
      // test` returns.
      const screenshotPath = filename.replace(/\.png$/, '');

      const flow = template
        .replaceAll('{{APP_ID}}', appId)
        .replaceAll('{{CLEAR_STATE}}', String(clearState))
        .replaceAll('{{LOGIN_STEPS}}', clearState ? loginStepsFor(role) : '# already logged in (clearState: false, see {{CLEAR_STATE}})')
        .replaceAll('{{REACH_STEPS}}', reachSteps)
        .replaceAll('{{ERROR_FILL_STEPS}}', errorSteps)
        .replaceAll('{{MASK_STEPS}}', '') // see platform-maestro.md "Known limits"
        .replaceAll('{{READY_SELECTOR}}', entry.ready || '')
        .replaceAll('{{SCREENSHOT_PATH}}', screenshotPath);

      const outPath = join(OUT_DIR, `${entry.id}__${state}__${role}.yaml`);
      writeFileSync(outPath, flow);
      lines.push(`FLOW ${outPath}`);
      count++;
    }
  }
}

for (const line of lines) process.stdout.write(line + '\n');
process.stdout.write(`GENERATE_RESULT=OK count=${count}\n`);
