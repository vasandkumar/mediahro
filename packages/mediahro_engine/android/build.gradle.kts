import java.nio.ByteBuffer
import java.nio.ByteOrder

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

// Native libraries per ABI: the mediahro-deps archive pinned in deps.lock
// (.deps-cache/android-<abi>/lib) or, until B4 publishes one, the ADR-004
// bootstrap (.deps-cache/bootstrap/android-<abi>/lib, tool/fetch_libmpv.py).
// Only the DT_NEEDED closure of the libraries the app opens is packaged
// (install-size budget, docs/11 §5): libmpv by default; lanes that open more
// add their roots with the Gradle property mediahroNativeLibs, e.g.
// mediahroNativeLibs=libvips.so,libsmb2.so in app/android/gradle.properties.
// Without either source the plugin builds and the engine reports libraryMissing.
val mediahroDeps = file("$projectDir/../../../.deps-cache").canonicalFile
val mediahroAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
val mediahroRoots =
    listOf("libmpv.so") +
        (findProperty("mediahroNativeLibs") as String?)
            .orEmpty()
            .split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
// A plain directory: AGP 9 refuses Providers in source sets.
val mediahroJni = layout.buildDirectory.dir("mediahro-jni").get().asFile

/** DT_NEEDED entries of a little-endian ELF shared object. */
fun elfNeeded(so: File): List<String> {
    val b = ByteBuffer.wrap(so.readBytes()).order(ByteOrder.LITTLE_ENDIAN)
    val is64 = b.get(4).toInt() == 2
    fun word(at: Int): Long = if (is64) b.getLong(at) else b.getInt(at).toLong() and 0xffffffffL
    val shoff = word(if (is64) 0x28 else 0x20).toInt()
    val shentsize = b.getShort(if (is64) 0x3A else 0x2E).toInt()
    val shnum = b.getShort(if (is64) 0x3C else 0x30).toInt()
    // Section header: name, type, flags, addr, offset, size, link.
    fun section(i: Int): LongArray {
        val o = shoff + i * shentsize
        return if (is64) {
            longArrayOf(b.getInt(o + 4).toLong(), b.getLong(o + 24), b.getLong(o + 32), b.getInt(o + 40).toLong())
        } else {
            longArrayOf(b.getInt(o + 4).toLong(), b.getInt(o + 16).toLong(), b.getInt(o + 20).toLong(), b.getInt(o + 24).toLong())
        }
    }
    val dynamic = (0 until shnum).map { section(it) }.firstOrNull { it[0] == 6L } ?: return emptyList()
    val strtab = section(dynamic[3].toInt())[1].toInt()
    val entry = if (is64) 16 else 8
    val names = mutableListOf<String>()
    for (k in 0 until (dynamic[2] / entry).toInt()) {
        val at = dynamic[1].toInt() + k * entry
        val tag = word(at)
        if (tag == 0L) break
        if (tag == 1L) {
            var end = strtab + word(at + entry / 2).toInt()
            val start = end
            while (b.get(end).toInt() != 0) end++
            names += String(ByteArray(end - start) { b.get(start + it) })
        }
    }
    return names
}

/** The libraries in [dir] reachable from [roots] through DT_NEEDED. */
fun closure(dir: File, roots: List<String>): Set<String> {
    val seen = mutableSetOf<String>()
    val todo = ArrayDeque(roots)
    while (todo.isNotEmpty()) {
        val name = todo.removeFirst()
        val so = File(dir, name)
        if (!so.isFile || !seen.add(name)) continue
        todo.addAll(elfNeeded(so))
    }
    return seen
}

val stageLibmpv =
    tasks.register<Sync>("mediahroStageLibmpv") {
        inputs.property("roots", mediahroRoots)
        for (abi in mediahroAbis) {
            val src =
                listOf(File(mediahroDeps, "android-$abi/lib"), File(mediahroDeps, "bootstrap/android-$abi/lib"))
                    .firstOrNull { File(it, "libmpv.so").exists() }
            if (src != null) {
                val keep = closure(src, mediahroRoots)
                from(src) {
                    include { it.name in keep }
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
