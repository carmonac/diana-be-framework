#!/usr/bin/env bash
# update-docs.sh — Convert docs/ markdown files into html_doc/ HTML pages
#
# Usage: ./tool/update-docs.sh
#
# Reads all markdown files from docs/ and generates a single-page
# HTML documentation site at html_doc/index.html.
#
# The home page (hero, features, quick start) is embedded in the converter.
# All other pages come from the markdown docs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs"
HTML_DIR="$PROJECT_ROOT/html_doc"

echo "Converting docs/ → html_doc/index.html..."

dart run "$SCRIPT_DIR/docs_to_html.dart" \
  --docs "$DOCS_DIR" \
  --output "$HTML_DIR/index.html"

echo "Done. Open $HTML_DIR/index.html in a browser."
