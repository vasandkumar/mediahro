#!/usr/bin/env bash
# Re-records the design-system and B3 screen goldens. Run on Linux (CI's
# host OS, where goldens compare near-exactly), e.g. inside WSL on Windows
# with Flutter from .fvmrc on PATH. Other hosts render text slightly
# differently; the comparator tolerates that locally but CI does not.
#
#   packages/mediahro_design/tool/record_goldens.sh
#
# Update goldens only with intent and review the PNG diff in the PR.
set -euo pipefail
cd "$(dirname "$0")/../../.."
if [ "$(uname -s)" != "Linux" ]; then
  echo "record_goldens: run on Linux (or WSL) so files match CI" >&2
  exit 1
fi
dart tools/l10n/merge_arb.dart
flutter pub get > /dev/null
(cd app && flutter gen-l10n > /dev/null)
(cd packages/mediahro_design && flutter test --tags golden --update-goldens)
(cd app && flutter test test/ui --update-goldens)
