#!/usr/bin/env bash
#
# normalize-suppression.sh — Normalize a suppression pattern into a semantic key.
#
# Two slightly-different formulations of the same issue should produce the same
# key, so they dedup as one suppression instead of two.
#
# Strategy:
#   1. Lowercase
#   2. Strip leading category bracket if present (e.g. "[Security]" -> "security")
#      and re-emit it as a "cat:" prefix.
#   3. Collapse whitespace runs to single space.
#   4. Strip trailing punctuation.
#   5. Drop tokens shorter than 3 chars (articles, "to", "of") to focus on content.
#   6. Drop common stop-words.
#   7. Keep the first 6 and last 3 content tokens, separated by a marker.
#      (Beginning describes "what", end usually describes "where".)
#
# Output: a stable key string on stdout.
# Usage:
#   echo "[Security] LIKE wildcard injection in Eloquent scope" | normalize-suppression.sh
#   # -> cat:security|like wildcard injection eloquent|scope
set -euo pipefail

input=$(cat)

# 1+2: extract category bracket
category=""
remainder="$input"
if [[ "$input" =~ ^\[([^]]+)\][[:space:]]*(.*)$ ]]; then
  category=$(echo "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  remainder="${BASH_REMATCH[2]}"
fi

# 3: lowercase + collapse whitespace
text=$(echo "$remainder" | tr '[:upper:]' '[:lower:]' | tr -s ' \t\n' ' ')

# 4: strip trailing punctuation
text=$(echo "$text" | sed -E 's/[[:punct:]]+$//')

# 5+6: drop short tokens and common stop-words
STOPWORDS="the a an of to in for at by on with from as is are be was were has have had this that these those it its his her their our your my will would could should may might can not no nor or and but so if then than when where how why what which who whom whose"
tokens=$(echo "$text" | tr ' ' '\n' | awk -v stop="$STOPWORDS" '
  BEGIN { split(stop, sw, " "); for (i in sw) S[sw[i]] = 1 }
  length($0) >= 3 && !S[$0] { print }
' | tr '\n' ' ')

# 7: keep first 6 + last 3
read -ra arr <<< "$tokens"
n=${#arr[@]}
head_part=""
tail_part=""
if (( n <= 9 )); then
  head_part="${arr[*]}"
else
  for ((i=0; i<6; i++)); do head_part+="${arr[i]} "; done
  for ((i=n-3; i<n; i++)); do tail_part+="${arr[i]} "; done
fi

head_part=$(echo "$head_part" | sed 's/ $//')
tail_part=$(echo "$tail_part" | sed 's/ $//')

if [ -n "$category" ]; then
  out="cat:$category|$head_part"
else
  out="$head_part"
fi
if [ -n "$tail_part" ]; then
  out="$out|$tail_part"
fi

echo "$out"
