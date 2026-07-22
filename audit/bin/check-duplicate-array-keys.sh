#!/usr/bin/env bash
#
# check-duplicate-array-keys.sh — deterministic duplicate-key scan for PHP
# translation arrays.
#
# Why this exists: PHP silently keeps the LAST value when an array literal
# repeats a key. `php -l` is happy, static review usually is too, and the
# damage only surfaces when a code path happens to read the shadowed key.
# A real incident: a duplicated `queue` key in a lang array crashed the admin
# failed-jobs view, but only once failed jobs actually existed.
#
# Detection uses PHP's own tokenizer rather than grep, so nested arrays,
# comments and interpolation do not produce false hits. Keys are compared per
# nesting level, which is what PHP does.
#
# Output:
#   DUPKEY_RESULT=OK | DUPLICATES | SKIP
#   For DUPLICATES: one line per hit: "DUPLICATE {file}:{line} key '{key}' (first seen line {first})"
#
# Usage: bash check-duplicate-array-keys.sh [PROJECT_ROOT]
set -uo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

command -v php >/dev/null 2>&1 || { echo "DUPKEY_RESULT=SKIP"; exit 0; }

BASE=""
for candidate in "$ROOT/resources/lang" "$ROOT/lang"; do
  [ -d "$candidate" ] && { BASE="$candidate"; break; }
done
[ -n "$BASE" ] || { echo "DUPKEY_RESULT=SKIP"; exit 0; }

FILES=$(find "$BASE" -name '*.php' -type f 2>/dev/null)
[ -n "$FILES" ] || { echo "DUPKEY_RESULT=SKIP"; exit 0; }

HITS=$(printf '%s\n' "$FILES" | php -r '
$found = [];
while (($file = fgets(STDIN)) !== false) {
    $file = trim($file);
    if ($file === "" || ! is_readable($file)) {
        continue;
    }

    $tokens = @token_get_all(file_get_contents($file));
    if (! is_array($tokens)) {
        continue;
    }

    // One frame per array nesting level, each holding key => first line seen.
    $stack = [];
    $depth = -1;
    $pendingKey = null;
    $pendingLine = 0;

    foreach ($tokens as $token) {
        if (is_array($token)) {
            [$id, $text, $line] = $token;

            if ($id === T_ARRAY) {
                continue; // the following "(" opens the frame
            }

            if ($id === T_CONSTANT_ENCAPSED_STRING) {
                $pendingKey = substr($text, 1, -1);
                $pendingLine = $line;
                continue;
            }

            if ($id === T_WHITESPACE || $id === T_COMMENT || $id === T_DOC_COMMENT) {
                continue;
            }

            if ($id === T_DOUBLE_ARROW) {
                if ($pendingKey !== null && $depth >= 0) {
                    if (isset($stack[$depth][$pendingKey])) {
                        $found[] = sprintf(
                            "DUPLICATE %s:%d key %s (first seen line %d)",
                            $file, $pendingLine, "\x27" . $pendingKey . "\x27", $stack[$depth][$pendingKey]
                        );
                    } else {
                        $stack[$depth][$pendingKey] = $pendingLine;
                    }
                }
                $pendingKey = null;
                continue;
            }

            // Any other token invalidates a half-collected key.
            $pendingKey = null;
            continue;
        }

        if ($token === "[" || $token === "(") {
            $depth++;
            $stack[$depth] = [];
            $pendingKey = null;
            continue;
        }

        if ($token === "]" || $token === ")") {
            if ($depth >= 0) {
                unset($stack[$depth]);
                $depth--;
            }
            $pendingKey = null;
            continue;
        }

        if ($token === ",") {
            $pendingKey = null;
            continue;
        }

        $pendingKey = null;
    }
}
echo implode("\n", $found);
' 2>/dev/null)

if [ -n "$HITS" ]; then
  echo "DUPKEY_RESULT=DUPLICATES"
  printf '%s\n' "$HITS"
else
  echo "DUPKEY_RESULT=OK"
fi
