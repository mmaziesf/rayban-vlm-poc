// Pure Kotlin/JVM: IntentRouter, FrameRingBuffer, GlanceController. No Android/DAT deps → fast JVM tests.
plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(17) }
// Tests use a dependency-free main() runner; see phone/README.md for the kotlinc one-liner.
