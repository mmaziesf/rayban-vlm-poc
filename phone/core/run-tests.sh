#!/usr/bin/env bash
# JVM tests for the pure-Kotlin core (no Gradle/Android SDK needed). Needs JDK 17 + kotlinc on PATH.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
kotlinc src/main/kotlin src/test/kotlin -include-runtime -d build/core-tests.jar 2>&1 | grep -v '^warning' || true
java -cp build/core-tests.jar glance.core.CoreTestsKt
