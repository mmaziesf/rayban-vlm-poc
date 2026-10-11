pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositories {
        google(); mavenCentral()
        // DAT (com.meta.wearable:mwdat-*) is on Maven Central — no token needed
        // (https://github.com/facebook/meta-wearables-dat-android README).
    }
}
rootProject.name = "glance"
include(":core", ":app")
