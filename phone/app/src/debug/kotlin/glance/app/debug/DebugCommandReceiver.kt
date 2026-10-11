package glance.app.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import glance.app.GlanceGraph
import glance.core.GlanceIntent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Holds the debug-only mock so the receiver can route through real DAT Speech. */
object DebugBus { @Volatile var mock: MockRig? = null }

/**
 * DEBUG ONLY. Lets the bot trigger turns without anyone speaking:
 *
 *   adb shell "am broadcast -a dev.arash.glance.DEBUG_COMMAND -n dev.arash.glance/glance.app.debug.DebugCommandReceiver --es text 'what am I seeing'"
 *   (quote the whole command: adb shell re-splits argv, so --es text "what am I seeing" arrives as "what")
 *   ... --es intent describe|log                 # → bypass router
 *   ... --es text "log this meal" --ez viaMockSpeech true   # → MockSpeechKit → DAT Speech → controller (full mock path)
 *   ... --ez heyMeta true                         # → MockVoiceInvocationKit.simulateLaunchAppAction() ("Hey Meta, start Glance")
 *   ... --es info vlm                             # → logs current VLM selection (stub/real + reason)
 *
 * Protected by android.permission.DUMP (granted to the adb shell, not to normal apps). See src/debug/AndroidManifest.xml.
 * Results appear in logcat: tag GlanceHud (one line per HUD state), tag GlanceDebug (receiver).
 */
class DebugCommandReceiver : BroadcastReceiver() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onReceive(context: Context, intent: Intent) {
        val text = intent.getStringExtra("text")
        val which = intent.getStringExtra("intent")
        val viaMock = intent.getBooleanExtra("viaMockSpeech", false)
        if (intent.getBooleanExtra("heyMeta", false)) {   // no controller needed: tests the invocation path itself
            Log.i("GlanceDebug", "heyMeta invocation=${DebugBus.mock?.heyMetaStartGlance() ?: "no mock"}"); return
        }
        if (intent.getStringExtra("info") == "vlm") { Log.i("GlanceDebug", "vlm=${GlanceGraph.vlmInfo}"); return }
        val c = GlanceGraph.controller
        Log.i("GlanceDebug", "cmd text=$text intent=$which viaMockSpeech=$viaMock controller=${c != null}")
        if (c == null) { Log.w("GlanceDebug", "loop not started — open the app first"); return }
        val pending = goAsync()
        scope.launch {
            try {
                when {
                    viaMock && text != null -> DebugBus.mock?.say(text) ?: Log.w("GlanceDebug", "no mock")
                    which == "describe" -> c.onCommand(GlanceIntent.Describe, "What am I seeing?")
                    which == "log" -> c.onCommand(GlanceIntent.LogMeal, "Log this meal")
                    text != null -> { c.onTranscription(text.substringBefore(' '), false); c.onTranscription(text, true) }
                    else -> Log.w("GlanceDebug", "nothing to do")
                }
            } finally { pending.finish() }
        }
    }
}
