#!/usr/bin/env bash
# Wrapper for `flutter run` that bundles the flavor + entry-point pair
# (which always travel together in this project) in one place. Any args
# after the flavor are forwarded verbatim to `flutter run`.
#
# Lives as a plain shell script rather than a melos script because melos
# doesn't forward stdin to script processes, so flutter's r/R/q hot-reload
# keystrokes don't reach it through `melos run ...`. A direct shell child
# of your terminal inherits stdin and works as expected.
#
# Usage:
#   tool/run-client.sh <dev|staging|prod> [flutter run args]
#
# Examples:
#   tool/run-client.sh dev
#   tool/run-client.sh staging -d chrome
#   tool/run-client.sh dev -d "$IPHONE_UDID" --release
#
# Device selection precedence: explicit `-d` / `--device-id` in args >
# FLUTTER_DEVICE env var > macos. `--flavor` is omitted when the
# resolved device is a web target (Chrome) because Flutter only
# supports it on Android, iOS, and macOS.

# `set -u` (unbound-variable check) is intentionally omitted: macOS ships
# bash 3.2 which trips on the empty-array idiom `"${arr[@]}"` we use for
# conditional flag passthrough. The variable surface here is too small to
# justify a workaround.
set -eo pipefail

flavor="${1:-}"
case "$flavor" in
  dev)     entry='main_development.dart'; native_flavor='development' ;;
  staging) entry='main_staging.dart';     native_flavor='staging' ;;
  prod)    entry='main_production.dart';  native_flavor='production' ;;
  '')      echo "usage: tool/run-client.sh <dev|staging|prod> [flutter run args]" >&2; exit 64 ;;
  *)       echo "unknown flavor: $flavor (expected dev|staging|prod)" >&2; exit 64 ;;
esac
shift

# Look for an explicit device id in the forwarded args so we know whether
# to inject our own `-d` and whether to drop `--flavor` (web targets).
device=''
prev=''
for arg in "$@"; do
  case "$prev" in
    -d|--device-id) device="$arg" ;;
  esac
  case "$arg" in
    --device-id=*) device="${arg#--device-id=}" ;;
  esac
  prev="$arg"
done

inject_device=()
if [ -z "$device" ]; then
  device="${FLUTTER_DEVICE:-macos}"
  inject_device=(-d "$device")
fi

flavor_arg=()
case "$device" in
  chrome|web-*) ;;
  *)            flavor_arg=(--flavor "$native_flavor") ;;
esac

cd "$(dirname "$0")/../apps/client"
exec flutter run "${flavor_arg[@]}" --target "lib/$entry" "${inject_device[@]}" "$@"
