package glance.core

/** Abstractions the Android/DAT layer implements. Core never touches DAT or LiteRT-LM directly. */

interface Clock { fun nowMs(): Long }
object SystemClock : Clock { override fun nowMs() = System.currentTimeMillis() }

data class FrameResult(val frame: Frame?, val note: String)

/** Somewhere a frame can come from on demand (e.g., DAT Photo / Stream.capturePhoto). May be slow. */
fun interface OnDemandCapture { fun capture(): Frame? }

data class VlmResult(val text: String, val prefillMs: Long = -1, val decodeMs: Long = -1)
interface VlmEngine { fun infer(frame: Frame?, prompt: String): VlmResult }

interface Speaker { fun speak(text: String) }
interface HudRenderer { fun render(state: HudState) }

data class MealEntry(val tsMs: Long, val name: String, val kcal: Int?, val proteinG: Int?, val frameTimeMs: Long, val rawJson: String)
interface MealLog { fun insert(entry: MealEntry): Int }
