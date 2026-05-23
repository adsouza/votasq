#!/usr/bin/env bash
# Starts the Firebase emulator suite alongside `tsc --watch` so changes
# under functions/src/ rebuild functions/lib/ continuously and the
# emulator hot-picks them up.
#
# Without this wrapper, the emulator reads functions/lib/ once at start
# and never re-checks it — so edits to src/ are invisible until you
# kill the emulator and run `npm run build`. The most painful version of
# this is silently calling a callable that doesn't exist in the loaded
# build yet (the client catches the error, the UI shows nothing).
#
# Usage:
#   tool/emulators.sh                           # auth,firestore,functions
#   tool/emulators.sh auth,firestore            # custom subset
#
# Press Ctrl+C to stop both the emulators and the background watcher.
#
# Persists emulator state to .emulator-data/ across restarts via
# --import + --export-on-exit. Without this, the emulator runs purely
# in-memory; the first restart wipes every seeded user and problem doc.
# The state directory is gitignored.

# `set -u` is intentionally omitted (macOS bash 3.2 trips on the empty
# arg case below — same constraint as tool/run-client.sh).
set -eo pipefail

cd "$(dirname "$0")/.."

only="${1:-auth,firestore,functions}"

echo "==> functions: initial tsc build"
(cd functions && npm run build)

echo "==> functions: starting tsc --watch in the background"
(cd functions && npm run build:watch) &
watch_pid=$!

# Kill the background watcher when this script exits, however it exits.
trap 'kill "$watch_pid" 2>/dev/null || true' EXIT INT TERM

# --import only loads if the directory already exists (no-op on first
# run); --export-on-exit writes the snapshot when the emulator stops
# cleanly via SIGINT/SIGTERM.
exec firebase emulators:start --only "$only" \
  --import=.emulator-data --export-on-exit=.emulator-data
