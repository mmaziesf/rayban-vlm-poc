package glance.app

import android.content.Context
import android.util.Log
import com.meta.wearable.dat.core.selectors.DeviceSelector
import glance.app.audio.AndroidSpeaker
import glance.app.dat.GlassesRig
import glance.app.hpl.MealStoreHolder
import glance.app.vlm.CannedVlmEngine
import glance.core.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Logs every HUD state as one parseable logcat line (tag GlanceHud) so the bot can assert flows from `adb logcat`. */
class LoggingHud(private val delegate: HudRenderer?, private val sink: (HudState) -> Unit = {}) : HudRenderer {
    override fun render(state: HudState) {
        val (text, meta) = when (state) {
            is HudState.Answer -> state.text to state.meta
            is HudState.Logged -> state.text to state.meta
            is HudState.Error -> state.message to ""
            is HudState.Idle -> "" to state.buffer.chip()
            is HudState.Listening -> state.partial to ""
            is HudState.Capturing -> state.utterance to ""
            is HudState.Processing -> state.utterance to ""
        }
        Log.i("GlanceHud", "state=${state.label} text=\"$text\" meta=\"$meta\"")
        sink(state)
        delegate?.render(state)
    }
}

/** Process-wide handles so debug tooling (broadcast receiver, tests) can reach the running loop. */
object GlanceGraph {
    @Volatile var controller: GlanceController? = null
    @Volatile var rig: GlassesRig? = null
    @Volatile var vlmInfo: String = "stub (default)"
    val buffer = FrameRingBuffer(capacity = 6) // 2 fps → ~3 s history

    /**
     * Starts the DAT session on [selector] and builds the controller.
     * [vlm]: MainActivity passes VlmFactory.build(...) (stub by default, real with -Pglance.vlm=real); tests use the default.
     */
    suspend fun start(
        context: Context, scope: CoroutineScope, selector: DeviceSelector,
        vlm: VlmEngine = CannedVlmEngine(), speaker: Speaker = AndroidSpeaker(context),
        hudSink: (HudState) -> Unit = {},
    ): GlanceController {
        val clock = SystemClock
        val rig = GlassesRig(context, scope, buffer, clock, streamFps = 2)
        lateinit var c: GlanceController
        val dat = rig.start(
            selector,
            onDescribe = { scope.launch(Dispatchers.Default) { c.onCommand(GlanceIntent.Describe, "What am I seeing?") } },
            onLog = { scope.launch(Dispatchers.Default) { c.onCommand(GlanceIntent.LogMeal, "Log this meal") } },
        )
        c = GlanceController(
            IntentRouter(), buffer, BufferedFrameSource(buffer, clock, rig.captureFallback(), maxAgeMs = 1500),
            vlm, LoggingHud(dat, hudSink), speaker, MealStoreHolder.get(context), clock, streamFps = rig.streamFps,
        )
        rig.controller = c
        this.rig = rig; controller = c
        c.showIdle()
        return c
    }
}
