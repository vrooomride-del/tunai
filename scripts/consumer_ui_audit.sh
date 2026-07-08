#!/usr/bin/env bash
# Consumer UI forbidden-term audit
# Scans ONLY consumer-visible feature files for engineering terms that must not appear in UI strings.
# Internal core logic files, factory screens, and DSP code are excluded.

set -euo pipefail

# Only scan these consumer-visible feature directories
SCAN_PATHS=(
  "lib/features/connect/"
  "lib/features/measure/"
  "lib/features/ai/"
  "lib/features/listen/"
  "lib/features/more/more_screen.dart"
  "lib/features/advanced/advanced_screen.dart"
  "lib/features/community/"
  "lib/features/library/"
  "lib/features/health/"
  "lib/features/auth/auth_screen.dart"
  "lib/features/onboarding/"
  "lib/shared/"
)

FORBIDDEN_TERMS=(
  "ADAU1701"
  "ADAU1466"
  "FRD"
  "ZMA"
  "T/S"
  "crossover"
  "크로스오버"
  "channel gain"
  "채널 게인"
  "LR4"
  "SafeLoad"
  "SPEAKER PROFILE"
  "PEQ"
  "T/S 파라미터"
  "Fs·Qts"
  "woofer FRD"
  "tweeter FRD"
  "WOO\b"
  "TWE\b"
)

FOUND=0

for path in "${SCAN_PATHS[@]}"; do
  if [[ ! -e "lib/../$path" && ! -e "$path" ]]; then continue; fi

  while IFS= read -r -d '' file; do
    for term in "${FORBIDDEN_TERMS[@]}"; do
      # Only match lines that contain string literals (inside quotes) - skip pure comments, debugPrint
      matches=$(grep -n "$term" "$file" 2>/dev/null \
        | grep -v "^[[:space:]]*//" \
        | grep -v "debugPrint\|logPrint" \
        | grep -v "^[[:space:]]*/\*" \
        | grep "'.*${term}.*'\|\".*${term}.*\"" || true)
      if [[ -n "$matches" ]]; then
        echo ""
        echo "VIOLATION in $file:"
        echo "$matches"
        FOUND=1
      fi
    done
  done < <(find "$path" -name "*.dart" -print0 2>/dev/null)
done

if [[ $FOUND -eq 0 ]]; then
  echo "✓ Consumer UI audit passed — no forbidden terms found in consumer-visible UI strings."
  exit 0
else
  echo ""
  echo "✗ Consumer UI audit FAILED — see violations above."
  exit 1
fi
