// Pure Kotlin/JVM: IntentRouter, FrameRingBuffer, GlanceController. No Android/DAT deps → fast JVM tests.
plugins { id("org.jetbrains.kotlin.jvm") }
kotlin { jvmToolchain(17) }
// Tests use a dependency-free main() runner; see phone/README.md for the kotlinc one-liner.

// `./gradlew :core:coreTests` runs the same main()-based checks as run-tests.sh (used by .github/workflows/android.yml).
tasks.register<JavaExec>("coreTests") {
    dependsOn("testClasses")
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("glance.core.CoreTestsKt")
}
