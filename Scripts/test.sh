#!/bin/sh
# Runs the tests. The Command Line Tools don't find the Swift Testing macro plugin
# on their own, so point the compiler at it when it's there.
set -eu
cd "$(dirname "$0")/.."

plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
