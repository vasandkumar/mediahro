group = "com.mediahro.mediahro_engine"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

// libmpv per ABI: the mediahro-deps archive pinned in deps.lock
// (.deps-cache/android-<abi>/lib) or, until B4 publishes it, the ADR-004
// bootstrap (.deps-cache/bootstrap/android-<abi>/lib, tool/fetch_libmpv.py).
// Without either the plugin builds and the engine reports libraryMissing.
val mediahroDeps = file("$projectDir/../../../.deps-cache").canonicalFile
val mediahroAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
val mediahroJni = layout.buildDirectory.dir("mediahro-jni")
val stageLibmpv =
    tasks.register<Sync>("mediahroStageLibmpv") {
        for (abi in mediahroAbis) {
            val src =
                listOf(File(mediahroDeps, "android-$abi/lib"), File(mediahroDeps, "bootstrap/android-$abi/lib"))
                    .firstOrNull { File(it, "libmpv.so").exists() }
            if (src != null) {
                from(src) {
                    include("*.so")
                    into(abi)
                }
            }
        }
        into(mediahroJni)
    }

android {
    namespace = "com.mediahro.mediahro_engine"

    compileSdk = 36
    ndkVersion = "28.2.13676358"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            jniLibs.srcDir(mediahroJni)
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 29
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

tasks.named("preBuild") { dependsOn(stageLibmpv) }

dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.mockito:mockito-core:5.0.0")
}
