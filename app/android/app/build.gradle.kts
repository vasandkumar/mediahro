plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

// Release signing (owner, docs/release/android-internal-test.md): the upload
// key comes from app/android/key.properties, which is gitignored and never
// committed. storeFile may be an absolute path outside the repo. Without the
// file (CI, lane builds) release builds fall back to the debug key.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use(::load)
}
val hasUploadKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }

/** Builds that may ship ML Kit (ADR-025 §5: store and direct). */
val mlKitFlavours = listOf("store", "direct")

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

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    // Proprietary ML Kit only where ADR-025 §5 allows it; the other builds
    // compile the stub (src/nomlkit) and use the open fallbacks.
    sourceSets {
        mlKitFlavours.forEach { getByName(it).java.srcDir("src/mlkit/kotlin") }
        (listOf("store", "direct", "foss", "enterprise") - mlKitFlavours).forEach {
            getByName(it).java.srcDir("src/nomlkit/kotlin")
        }
    }

    buildTypes {
        release {
            // The owner's upload key when key.properties is present; otherwise
            // the debug key, so CI and lane release builds stay installable.
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        resources {
            // Library build metadata several jars carry; not needed at runtime.
            excludes += setOf("META-INF/DEPENDENCIES", "META-INF/INDEX.LIST")
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2")
    implementation("androidx.media3:media3-session:1.11.1")
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.browser:browser:1.8.0")
    // SFTP (ADR-017): sshj over the platform JCA; no bundled crypto provider.
    implementation("com.hierynomus:sshj:0.41.2") {
        exclude(group = "org.bouncycastle")
    }

    // Debug builds only: a local SFTP server for the SftpFacade device tests.
    debugImplementation("org.apache.sshd:sshd-sftp:2.20.0")

    // On-device OCR, language ID and translation (SUB-051/053); proprietary,
    // so only in mlKitFlavours. Recognisers come with Play services.
    mlKitFlavours.forEach { flavour ->
        add("${flavour}Implementation", "org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-text-recognition-chinese:16.0.1")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-text-recognition-devanagari:16.0.1")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-text-recognition-japanese:16.0.1")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-text-recognition-korean:16.0.1")
        add("${flavour}Implementation", "com.google.android.gms:play-services-mlkit-language-id:17.0.0")
        add("${flavour}Implementation", "com.google.mlkit:translate:17.0.3")
    }

    // JVM unit tests of the modules' pure rules (./gradlew :app:testFossDebugUnitTest).
    testImplementation("junit:junit:4.13.2")
}
