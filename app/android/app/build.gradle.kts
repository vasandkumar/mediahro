plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mediahro.mediahro"
    compileSdk = flutter.compileSdkVersion
    // NDK r28+ for 16 KB page alignment (docs/07 §1 rule 4).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mediahro.app"
        // API 29 is the minimum tested OS (docs/11 §3); target API 36 (docs/07 §3.2).
        minSdk = 29
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Build flavours (docs/05 §11). Pair each with --dart-define=MEDIAHRO_FLAVOR=<name>.
    flavorDimensions += "distribution"
    productFlavors {
        create("store") {
            dimension = "distribution"
        }
        create("direct") {
            dimension = "distribution"
        }
        create("foss") {
            dimension = "distribution"
        }
        create("enterprise") {
            dimension = "distribution"
            applicationIdSuffix = ".enterprise"
        }
    }

    buildTypes {
        release {
            // Release signing comes from CI secrets (owner task, STATUS.md section 4).
            // Local and CI test builds fall back to the debug key so they stay installable.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Platform modules (docs/05 §8, lane C4a): Kotlin + coroutines + Media3, no Java.
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.fragment:fragment-ktx:1.8.8")
}
