#!/bin/bash
# Build + install ClawBar. Re-run anytime to update.
set -e
cd "$(dirname "$0")"
swift build -c release
.build/release/clawbar install
