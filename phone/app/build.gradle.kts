plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }

android {
    namespace = "glance.app"
    compileSdk = 35
    defaultConfig {
        applicationId = "dev.arash.glance"; minSdk = 29; targetSdk = 35; versionCode = 1; versionName = "0.2-m2"
        // Developer Mode: attestation unused, both may be 0 (https://wearables.developer.meta.com/docs/develop/dat/build-integration-android/)
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") } // phone + x86_64 emulator; drops 32-bit libs
        manifestPlaceholders["mwdat_application_id"] = "0"
        manifestPlaceholders["mwdat_client_token"] = "0"
    }
    buildTypes { debug { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}
kotlin { jvmToolchain(17) }

dependencies {
    implementation(project(":core"))
    implementation(libs.mwdat.core)
    implementation(libs.mwdat.camera)
    implementation(libs.mwdat.display)
    implementation(libs.mwdat.speech)
    debugImplementation(libs.mwdat.mockdevice)   // Mock Device Kit only in debug builds (code in src/debug)
    androidTestImplementation(libs.mwdat.mockdevice)
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("junit:junit:4.13.2")
    implementation(libs.litertlm.android)
    implementation(libs.coroutines.android)
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
}
