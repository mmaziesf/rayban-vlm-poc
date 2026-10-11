package glance.app.dat

import com.meta.wearable.dat.display.Display
import com.meta.wearable.dat.display.views.*
import glance.core.HudRenderer
import glance.core.HudState
import kotlinx.coroutines.runBlocking

/**
 * Renders core HudState onto Meta Ray-Ban Display via DAT Display (sendContent replaces the whole view).
 * Layout mirrors webapp/: info column (left, grows) + action buttons (right). API per
 * https://wearables.developer.meta.com/docs/develop/dat/display-android/
 * Note: display dims at 20 s and sleeps at 25 s of inactivity; Back (two-finger tap) ENDS the display session.
 */
class DatHudRenderer(
    private val display: Display,
    private val onDescribe: () -> Unit,
    private val onLog: () -> Unit,
) : HudRenderer {

    override fun render(state: HudState) {
        val (prompt, body, meta) = when (state) {
            is HudState.Idle -> Triple("Say “what am I seeing?”", "", state.buffer.chip())
            is HudState.Listening -> Triple(state.partial.ifBlank { "…" }, "", "")
            is HudState.Capturing -> Triple(state.utterance, "", "")
            is HudState.Processing -> Triple(state.utterance, "", "")
            is HudState.Answer -> Triple(state.utterance, state.text, state.meta)
            is HudState.Logged -> Triple(state.utterance, state.text, state.meta)
            is HudState.Error -> Triple("", state.message, "")
        }
        val busy = state is HudState.Capturing || state is HudState.Processing
        // sendContent is suspend; render() is called from the controller's background thread, so block to keep HUD order.
        runBlocking { display.sendContent {
            flexBox(direction = Direction.ROW, gap = 16, padding = 16) {
                flexBox(direction = Direction.COLUMN, gap = 10, flexGrow = 3f) {
                    text(state.label.uppercase(), style = TextStyle.META)
                    if (prompt.isNotBlank()) text(prompt, style = TextStyle.BODY, color = TextColor.SECONDARY)
                    if (body.isNotBlank()) text(body, style = TextStyle.HEADING)
                    if (meta.isNotBlank()) text(meta, style = TextStyle.META, color = TextColor.SECONDARY)
                }
                if (!busy) {
                    flexBox(direction = Direction.COLUMN, gap = 12, flexGrow = 2f, alignment = Alignment.CENTER) {
                        // VERIFY: IconName constants. Only ARROW_LEFT/ARROW_RIGHT/CHECKMARK_CIRCLE/BELL/GEAR/HEART are confirmed in docs.
                        button(label = "What am I seeing?", style = ButtonStyle.PRIMARY, onClick = { onDescribe() })
                        button(label = "Log this meal", style = ButtonStyle.SECONDARY, onClick = { onLog() })
                    }
                }
            }
        }.fold(onSuccess = {}, onFailure = { error, _ -> android.util.Log.w("Glance", "display: ${error.description}") }) }
    }
}
