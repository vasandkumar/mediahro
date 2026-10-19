package com.mediahro.mediahro_engine

import android.content.Context
import android.system.ErrnoException
import android.system.Os
import java.io.File

/**
 * libass in the mediahro-deps Android build finds fonts through fontconfig,
 * which has no configuration on Android. Writes one that indexes the system
 * fonts with a writable cache in the app's cache directory and points
 * fontconfig at it, before the first libmpv core starts (SUB-010, SUB-014).
 */
internal object FontConfig {
    private val fontDirs = listOf("/system/fonts", "/product/fonts", "/system_ext/fonts")

    fun prepare(context: Context) {
        try {
            val dir = File(context.filesDir, "fontconfig").apply { mkdirs() }
            val cache = File(context.cacheDir, "fontconfig").apply { mkdirs() }
            val conf = File(dir, "fonts.conf")
            val text = config(cache)
            if (!conf.exists() || conf.readText() != text) conf.writeText(text)
            Os.setenv("FONTCONFIG_FILE", conf.absolutePath, true)
            Os.setenv("FONTCONFIG_PATH", dir.absolutePath, true)
        } catch (e: ErrnoException) {
            // Without fontconfig libass falls back to embedded fonts only.
        } catch (e: java.io.IOException) {
            // Same fallback when app storage is unavailable.
        }
    }

    private fun config(cache: File): String =
        buildString {
            appendLine("<?xml version=\"1.0\"?>")
            appendLine("<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">")
            appendLine("<fontconfig>")
            for (d in fontDirs) appendLine("  <dir>$d</dir>")
            appendLine("  <cachedir>${cache.absolutePath}</cachedir>")
            for (generic in listOf("sans-serif", "serif", "monospace")) {
                val preferred =
                    when (generic) {
                        "serif" -> "Noto Serif"
                        "monospace" -> "Droid Sans Mono"
                        else -> "Roboto"
                    }
                appendLine("  <alias><family>$generic</family><prefer><family>$preferred</family></prefer></alias>")
            }
            appendLine("</fontconfig>")
        }
}
