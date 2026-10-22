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

    // Only the store flavour links Play Billing (docs/07 rule 5); the others
    // share a no-op PurchasesBinding from src/noBilling.
    sourceSets {
        for (flavour in listOf("direct", "foss", "enterprise")) {
            getByName(flavour).java.srcDir("src/noBilling/kotlin")
        }
        // Start-up diagnostics (media permissions and what the MediaStore shows): debug and
        // profile builds only, never release.
        for (type in listOf("debug", "profile")) {
            getByName(type).java.srcDir("src/diagnostics/kotlin")
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

// Play Billing drags in Google's usage-reporting pipeline (Data Transport with the CCT
// backend that uploads) and the location client. The app has no telemetry (docs/09, PRIV-004),
// so the uploader and the location client are kept out of every APK. The billing library only
// links transport-api/-runtime; with no backend registered its events have nowhere to go.
// tools/compliance/check_classpath.py fails the build if any of these returns.
configurations.configureEach {
    exclude(group = "com.google.android.datatransport", module = "transport-backend-cct")
    exclude(group = "com.google.firebase", module = "firebase-encoders-json")
    exclude(group = "com.google.firebase", module = "firebase-encoders-proto")
    exclude(group = "com.google.android.gms", module = "play-services-location")
    exclude(group = "com.google.android.gms", module = "play-services-places-placereport")
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
    // HEIC encode (IMG-010/015, ADR-037): the platform encoder behind a small wrapper; Apache-2.0.
    implementation("androidx.heifwriter:heifwriter:1.1.0")
    // Scheduled background jobs (ADR-049): WorkManager, Apache-2.0, no network or telemetry.
    implementation("androidx.work:work-runtime-ktx:2.10.2")
    // Tips and the supporter subscription (SUP-002): the Play rail, store flavour only.
    // The library only talks to the Play Store app on the device.
    "storeImplementation"("com.android.billingclient:billing-ktx:9.1.0")
    // SFTP (ADR-017): sshj over the platform JCA; no bundled crypto provider.
    implementation("com.hierynomus:sshj:0.41.2") {
        exclude(group = "org.bouncycastle")
    }
    // JcaSshConfig hands sshj no-op loggers (`org.slf4j.Logger`, `NOPLogger`), so the API is
    // compiled against explicitly. It used to reach the classpath only through the debug-only
    // sshd-sftp below, which broke every release and profile build.
    implementation("org.slf4j:slf4j-api:2.0.17")

    // Debug builds only: a local SFTP server for the SftpFacade device tests.
    debugImplementation("org.apache.sshd:sshd-sftp:2.20.0")

    // JVM unit tests of the modules' pure rules (./gradlew :app:testFossDebugUnitTest).
    testImplementation("junit:junit:4.13.2")
}

// No telemetry or location library, and no test library, may ship in a release build (docs/09,
// PRIV-004). Fails every release build if one reaches a release runtime classpath again.
// The profile build keeps integration_test (and with it junit) for the device tests.
val bannedInRelease = listOf(
    "com.google.android.datatransport:transport-backend-cct",
    "com.google.android.gms:play-services-location",
    "com.google.android.gms:play-services-places-placereport",
    "com.google.firebase:firebase-encoders-json",
    "com.google.firebase:firebase-encoders-proto",
    "junit:junit",
    "org.hamcrest:hamcrest-core",
    "org.hamcrest:hamcrest-library",
    "org.hamcrest:hamcrest-integration",
)
val verifyReleaseClasspaths = tasks.register("verifyReleaseClasspaths") {
    group = "verification"
    description = "Fails when a telemetry, location or test library is on a release runtime classpath."
    doLast {
        val found = sortedSetOf<String>()
        for (flavour in listOf("store", "direct", "foss", "enterprise")) {
            val name = "${flavour}ReleaseRuntimeClasspath"
            val config = configurations.findByName(name) ?: continue
            for (component in config.incoming.resolutionResult.allComponents) {
                val id = component.moduleVersion ?: continue
                if ("${id.group}:${id.name}" in bannedInRelease) found += "$name: ${id.group}:${id.name}:${id.version}"
            }
        }
        if (found.isNotEmpty()) {
            throw GradleException("Banned libraries on a release classpath: " + found.joinToString("; "))
        }
    }
}
afterEvaluate {
    tasks.matching { it.name in setOf("preStoreReleaseBuild", "preDirectReleaseBuild", "preFossReleaseBuild", "preEnterpriseReleaseBuild") }
        .configureEach { dependsOn(verifyReleaseClasspaths) }
}
