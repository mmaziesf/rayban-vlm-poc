package glance.app.debug

import android.content.Context
import android.net.Uri
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.LinkState
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import com.meta.wearable.dat.mockdevice.api.GlassesModel
import com.meta.wearable.dat.mockdevice.api.MockDeviceKitConfig
import com.meta.wearable.dat.mockdevice.api.MockGlasses
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import java.io.File

/**
 * DEBUG ONLY (src/debug): simulated Meta Ray-Ban Display, no hardware, no Meta AI registration.
 *  - MockDeviceKitConfig(initiallyRegistered = true, initialPermissionsGranted = true) skips registration/consent.
 *  - Display preview → Chrome simulator at http://127.0.0.1:9000/ after `adb forward tcp:9000 tcp:9000`.
 *  - Camera → bundled H.265 clip (assets/mock_feed_hevc.mp4), copied to cacheDir and passed as a file:// Uri.
 *  - Still capture (Stream.capturePhoto fallback) → assets/mock_photo_meal.jpg via setCapturedImage.
 *  - Speech → services.speech.simulateTranscription (delivered only while isListening).
 *  - "Hey Meta, start Glance" → services.voiceInvocation.simulateLaunchAppAction().
 * API checked against mwdat-mockdevice-1.0.1 (javap).
 */
class MockRig(private val context: Context) {
    private val kit = MockDeviceKit.getInstance(context.applicationContext)
    var glasses: MockGlasses? = null; private set

    /** Pairs the mock, powers/dons it, sets media, starts the preview server, and waits until DAT sees it CONNECTED. */
    suspend fun startAndAwait(port: Int = 9000, timeoutMs: Long = 15_000): DeviceIdentifier {
        kit.enable(MockDeviceKitConfig(true, true))
        val g = kit.pairGlasses(GlassesModel.META_RAYBAN_DISPLAY).getOrThrow()
        glasses = g
        g.powerOn(); g.unfold(); g.don()
        g.services.camera.setCameraFeed(Uri.fromFile(assetToCache("mock_feed_hevc.mp4")))
        g.services.camera.setCapturedImage(Uri.fromFile(assetToCache("mock_photo_meal.jpg")))
        // Preview server is optional (Chrome simulator only); never block the loop on it.
        runCatching { kit.startTestServer(port).getOrThrow() }
            .onFailure { android.util.Log.w("GlanceDebug", "MDK test server not started (preview unavailable): ${it.message}") }
        val id = g.deviceIdentifier
        withTimeout(timeoutMs) {
            while (Wearables.devicesMetadata[id]?.value?.linkState != LinkState.CONNECTED) delay(100)
        }
        return id
    }

    /** Simulate the wearer speaking: progressive partials, then the final. Waits for the Speech session to listen. */
    suspend fun say(text: String, timeoutMs: Long = 10_000) {
        val speech = glasses?.services?.speech ?: error("mock not started")
        withTimeout(timeoutMs) { while (!speech.isListening) delay(50) }
        val words = text.split(" ")
        for (i in 1 until words.size) { speech.simulateTranscription(words.take(i).joinToString(" "), false, 0.9f); delay(120) }
        speech.simulateTranscription(text, true, 0.95f)
    }

    fun heyMetaStartGlance(): String? = glasses?.services?.voiceInvocation?.simulateLaunchAppAction()

    fun stop() { runCatching { kit.stopTestServer() }; runCatching { kit.disable() } }

    private fun assetToCache(name: String): File {
        val out = File(context.cacheDir, name)
        if (!out.exists() || out.length() == 0L) context.assets.open(name).use { i -> out.outputStream().use { i.copyTo(it) } }
        return out
    }
}
