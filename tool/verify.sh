#!/usr/bin/env bash
# Full verification: resolve, generate, analyze, test.
# Usage: tool/verify.sh (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> dart pub get"
dart pub get

for example in todo_api greeter_grpc; do
  echo "==> build_runner build (examples/$example)"
  (cd "examples/$example" && dart run build_runner build)
done

echo "==> dart analyze"
dart analyze --fatal-infos

for package in diana diana_generator diana_grpc; do
  echo "==> tests: packages/$package"
  (cd "packages/$package" && dart test)
done

for example in todo_api greeter_grpc; do
  echo "==> tests: examples/$example"
  (cd "examples/$example" && dart test)
done

for example in todo_api greeter_grpc; do
  echo "==> determinism: examples/$example rebuild must be byte-identical"
  (
    cd "examples/$example"
    find lib \( -name "*.diana*.dart" -o -name "*.g.dart" \) | sort \
      | xargs shasum > "/tmp/diana_determinism_${example}_1"
    find lib \( -name "*.diana*.dart" -o -name "*.g.dart" \) -delete
    dart run build_runner build > /dev/null
    find lib \( -name "*.diana*.dart" -o -name "*.g.dart" \) | sort \
      | xargs shasum > "/tmp/diana_determinism_${example}_2"
    diff "/tmp/diana_determinism_${example}_1" "/tmp/diana_determinism_${example}_2"
  )
done

echo "==> OK"
