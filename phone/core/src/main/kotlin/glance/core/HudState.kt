package glance.core

/** Mirrors webapp/ states 1:1 so the web prototype and DAT Display HUD stay in sync. */
sealed class HudState {
    abstract val label: String
    data class Idle(val buffer: BufferStatus) : HudState() { override val label = "Ready" }
    data class Listening(val partial: String) : HudState() { override val label = "Listening" }
    data class Capturing(val utterance: String) : HudState() { override val label = "Capturing" }
    data class Processing(val utterance: String) : HudState() { override val label = "Thinking" }
    data class Answer(val utterance: String, val text: String, val meta: String) : HudState() { override val label = "Answer" }
    data class Logged(val utterance: String, val text: String, val meta: String) : HudState() { override val label = "Logged" }
    data class Error(val message: String) : HudState() { override val label = "Error" }
}

data class BufferStatus(val live: Boolean, val fps: Int, val lastFrameAgeMs: Long?) {
    fun chip(): String = when {
        !live -> "Camera off"
        lastFrameAgeMs == null -> "Live · waiting"
        else -> "Live ${fps} fps · ${"%.1f".format(lastFrameAgeMs / 1000.0)} s"
    }
}
