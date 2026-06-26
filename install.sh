#!/bin/bash
# Build + install claude-status-bar. Re-run anytime to update.
set -e
cd "$(dirname "$0")"
swift build -c release
.build/release/claude-status-bar install
