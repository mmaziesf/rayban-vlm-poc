#!/usr/bin/env bash
# Linux (bot box) or macOS: build + unit-test the platform-neutral Swift core.
# Box toolchain: Swift 6.4.0 (swift.org Debian 13 tarball) in ~/swift.
# Workaround: the 6.4 default build system ("swiftbuild") can't locate swiftc in the tarball layout → use the native one.
set -euo pipefail
cd "$(dirname "$0")"
SWIFT=${SWIFT:-$(command -v swift || echo "$HOME/swift/bin/swift")}
if [[ "$(uname)" == Linux ]]; then
  exec env -i HOME="$HOME" PATH="$(dirname "$SWIFT"):/usr/bin:/bin" TERM=dumb "$SWIFT" test --build-system native "$@"
else
  exec swift test "$@"
fi
