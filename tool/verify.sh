#!/usr/bin/env bash
# Full verification: resolve, generate, analyze, test.
# Usage: tool/verify.sh (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> dart pub get"
dart pub get

echo "==> build_runner build (examples/todo_api)"
(cd examples/todo_api && dart run build_runner build)

echo "==> dart analyze"
dart analyze --fatal-infos

echo "==> tests: packages/diana"
(cd packages/diana && dart test)

echo "==> tests: packages/diana_generator"
(cd packages/diana_generator && dart test)

echo "==> tests: examples/todo_api"
(cd examples/todo_api && dart test)

echo "==> OK"
