package glance.core

/** What the wearer asked for. Vision intents need a frame. */
sealed class GlanceIntent {
    abstract val needsFrame: Boolean
    object Describe : GlanceIntent() { override val needsFrame = true; override fun toString() = "Describe" }
    object LogMeal : GlanceIntent() { override val needsFrame = true; override fun toString() = "LogMeal" }
    data class Chat(val text: String) : GlanceIntent() { override val needsFrame = false }
    data class Unknown(val text: String) : GlanceIntent() { override val needsFrame = false }
}

/**
 * Maps glasses ASR transcripts (DAT Speech capability) to intents.
 * Deterministic keyword/regex matching keeps M2 offline and testable; the VLM is not used for routing.
 */
class IntentRouter(private val minConfidence: Float = 0.4f) {

    private val describe = listOf(
        Regex("""\bwhat(?:'s| is| am i| are we)? (?:i'?m |am i )?(?:seeing|looking at|in front of me)\b"""),
        Regex("""\bwhat do (?:i|you) see\b"""),
        Regex("""\bdescribe (?:this|that|what i see|the scene|it)\b"""),
        Regex("""\bwhat(?:'s| is) (?:this|that)\b"""),
    )
    private val logMeal = listOf(
        Regex("""^(?:please )?log (?:what|it\b)"""),
        Regex("""\blog (?:this|that|my)(?: (?:meal|food|plate|lunch|dinner|breakfast|snack))?\b"""),
        Regex("""\b(?:save|record|track) (?:this|my) (?:meal|food|plate|lunch|dinner|breakfast|snack)\b"""),
    )

    fun normalize(text: String): String =
        text.lowercase()
            .replace('’', '\'')
            .replace(Regex("""^(?:hey meta[, ]*|ok(?:ay)? glance[, ]*|glance[, ]*)"""), "")
            .replace(Regex("""[^a-z0-9' ]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()

    /** Route a FINAL transcript. Partial transcripts should go to [isVisionHint] only. */
    fun route(text: String, confidence: Float = 1f): GlanceIntent {
        val t = normalize(text)
        if (t.isEmpty() || confidence < minConfidence) return GlanceIntent.Unknown(text)
        // "log this" is checked first: "log what I'm looking at" is a log request, not a describe.
        if (logMeal.any { it.containsMatchIn(t) }) return GlanceIntent.LogMeal
        if (describe.any { it.containsMatchIn(t) }) return GlanceIntent.Describe
        return GlanceIntent.Chat(text.trim())
    }

    /** Cheap early signal on a PARTIAL transcript, used to pin/arm the frame buffer before the final arrives. */
    fun isVisionHint(partial: String): Boolean {
        val t = normalize(partial)
        return t.startsWith("what") || t.startsWith("log") || t.startsWith("describe")
    }
}
