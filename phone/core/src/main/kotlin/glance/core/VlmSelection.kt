package glance.core

/**
 * Decides stub vs real VLM (M1c). Pure so it is JVM-unit-tested; the app feeds it BuildConfig, an optional
 * debug launch extra, and what it found on disk / in RAM.
 *  - "stub": always the canned engine (emulator, CI, instrumented tests stay deterministic + green).
 *  - "real": LiteRT-LM only if a complete model file is present and the device has enough RAM; otherwise
 *            fall back to stub WITH a reason that is logged + shown on the HUD meta (never silently).
 */
object VlmSelection {
    enum class Mode { STUB, REAL }
    data class Candidate(val path: String, val exists: Boolean, val sizeBytes: Long)
    data class Decision(val mode: Mode, val modelPath: String?, val reason: String)

    fun parseMode(s: String?): Mode? = when (s?.trim()?.lowercase()) {
        "real", "litert", "e4b" -> Mode.REAL
        "stub", "canned", "mock" -> Mode.STUB
        else -> null
    }

    fun decide(
        buildDefault: String, override: String?, candidates: List<Candidate>,
        expectedSizeBytes: Long?, availRamBytes: Long?, minRamBytes: Long = 3L shl 30,
    ): Decision {
        val requested = parseMode(override) ?: parseMode(buildDefault) ?: Mode.STUB
        val src = if (parseMode(override) != null) "override" else "build"
        if (requested == Mode.STUB) return Decision(Mode.STUB, null, "stub ($src)")
        val found = candidates.firstOrNull { it.exists }
            ?: return Decision(Mode.STUB, null, "real requested ($src) but no model at ${candidates.joinToString { it.path }}")
        if (expectedSizeBytes != null && found.sizeBytes != expectedSizeBytes)
            return Decision(Mode.STUB, null, "model incomplete: ${found.sizeBytes}/$expectedSizeBytes bytes at ${found.path}")
        if (availRamBytes != null && availRamBytes < minRamBytes)
            return Decision(Mode.STUB, null, "low RAM: ${availRamBytes shr 20} MB available < ${minRamBytes shr 20} MB")
        return Decision(Mode.REAL, found.path, "real ($src) ${found.path}")
    }
}
