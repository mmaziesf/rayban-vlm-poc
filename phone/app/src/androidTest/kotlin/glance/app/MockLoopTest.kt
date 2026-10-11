package glance.app

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.SpecificDeviceSelector
import glance.app.debug.MockRig
import glance.core.*
import kotlinx.coroutines.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * End-to-end on Mock Device Kit (no glasses, no Meta AI registration):
 * mock RBD → DAT session (Display + 2 fps Camera stream from bundled H.265 + Speech) → GlanceController (canned VLM).
 * Run: ./gradlew :app:connectedDebugAndroidTest   (needs an emulator or a phone on adb)
 * Slow devices (TCG emulator on the bot box): add -Pandroid.testInstrumentationRunnerArguments.timeoutScale=6
 *   or `am instrument -e timeoutScale 6 ...` — each DAT display render takes ~1.5-3 s under software emulation.
 */
@RunWith(AndroidJUnit4::class)
class MockLoopTest {
    private val ctx = InstrumentationRegistry.getInstrumentation().targetContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val states = CopyOnWriteArrayList<HudState>()
    private lateinit var mock: MockRig
    private val scale = (InstrumentationRegistry.getArguments().getString("timeoutScale") ?: "1").toLong()
    private val silent = object : Speaker { val said = CopyOnWriteArrayList<String>(); override fun speak(text: String) { said += text } }

    @Before fun setUp() = runBlocking {
        Wearables.initialize(ctx)
        mock = MockRig(ctx)
        val id = withTimeout(20_000 * scale) { mock.startAndAwait(timeoutMs = 15_000 * scale) }
        GlanceGraph.buffer.clear()
        val base = GlanceGraph.buffer.totalPushed // cumulative across tests; clear() doesn't reset it
        withTimeout(20_000 * scale) { GlanceGraph.start(ctx, scope, SpecificDeviceSelector(id), speaker = silent, hudSink = { states += it }) }
        // Stream must be delivering frames from the mock H.265 feed before we ask anything.
        withTimeout(15_000 * scale) { while (GlanceGraph.buffer.totalPushed < base + 2) delay(100) }
    }

    @After fun tearDown() { scope.cancel(); GlanceGraph.controller = null; mock.stop() }

    private suspend fun awaitTerminal(timeoutMs: Long = 15_000 * scale): HudState = withTimeout(timeoutMs) {
        while (true) {
            states.lastOrNull()?.let { if (it is HudState.Answer || it is HudState.Logged || it is HudState.Error) return@withTimeout it }
            delay(50)
        }
        @Suppress("UNREACHABLE_CODE") error("unreachable")
    }

    @Test fun displayIdleShowsLiveBuffer() {
        val idle = states.filterIsInstance<HudState.Idle>().firstOrNull()
        assertNotNull("Idle rendered", idle)
        assertTrue("buffer frames arriving", GlanceGraph.buffer.latest() != null)
        assertEquals(FrameOrigin.STREAM_BUFFER, GlanceGraph.buffer.latest()!!.origin)
    }

    @Test fun speechDescribeUsesBufferedFrame() = runBlocking {
        states.clear()
        mock.say("what am I seeing", timeoutMs = 10_000 * scale)
        val end = awaitTerminal()
        val labels = states.map { it.label }
        assertTrue("got Answer, not $end", end is HudState.Answer)
        val i = labels.indexOf("Capturing")
        assertTrue("sequence $labels", labels.first() == "Listening" && i > 0 && labels.subList(i, labels.size) == listOf("Capturing", "Thinking", "Answer"))
        val meta = (end as HudState.Answer).meta
        assertTrue("frame source should be pinned/buffer, was: $meta", meta.startsWith("pinned") || meta.startsWith("buffer"))
        // TTS fires after the (slow, on emulator) display render; the sink sees Answer first.
        withTimeout(10_000 * scale) { while (silent.said.isEmpty()) delay(50) }
        assertTrue("spoken", silent.said.isNotEmpty())
    }

    @Test fun speechLogMealLogs() = runBlocking {
        states.clear()
        mock.say("log this meal", timeoutMs = 10_000 * scale)
        val end = awaitTerminal()
        assertTrue("got Logged, not $end", end is HudState.Logged)
    }

    @Test fun debugCommandPathWithoutSpeech() = runBlocking {
        // Same path DebugCommandReceiver uses for `adb shell am broadcast … --es text "what am I seeing"`.
        states.clear()
        val c = GlanceGraph.controller!!
        withContext(Dispatchers.Default) { c.onTranscription("what", false); c.onTranscription("what am I seeing", true) }
        val end = awaitTerminal()
        assertTrue(end is HudState.Answer)
        assertFalse("must not need slow capture", (end as HudState.Answer).meta.startsWith("capture-fallback"))
    }
}
