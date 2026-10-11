package glance.app.audio

import android.content.Context
import android.speech.tts.TextToSpeech
import glance.core.Speaker
import java.util.Locale

/**
 * Phone TTS → glasses speakers over Bluetooth A2DP (high quality). Do not enable HFP for output:
 * HFP drops audio to 8 kHz mono (https://wearables.developer.meta.com/docs/develop/dat/microphones-and-speakers/).
 * Offline: install an on-device English voice in Android TTS settings.
 */
class AndroidSpeaker(context: Context) : Speaker {
    private var ready = false
    private val tts = TextToSpeech(context) { status -> ready = status == TextToSpeech.SUCCESS }.apply { language = Locale.US }
    override fun speak(text: String) { if (ready) tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "glance") }
    fun shutdown() = tts.shutdown()
}
