package glance.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.voiceinvocations.VoiceInvocationsStream
import com.meta.wearable.dat.core.voiceinvocations.isVoiceInvocationsIntent
import com.meta.wearable.dat.core.voiceinvocations.startVoiceInvocationsStream
import com.meta.wearable.dat.core.voiceinvocations.types.actions.LaunchApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Phone-side console + wiring. Debug builds: Mock Device Kit RBD auto-starts (no glasses, no registration).
 * Release builds: real glasses via AutoDeviceSelector (registration/permission flow still TODO for H6).
 * "Hey Meta, start Glance" → voice invocation (Wearables-level stream; answered exactly once).
 */
class MainActivity : ComponentActivity() {
    private lateinit var status: TextView
    private lateinit var dev: DevHooks
    private var invocations: VoiceInvocationsStream? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        status = TextView(this)
        val ui = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 32, 32, 32) }
        ui.addView(status)
        setContentView(ui)

        Wearables.initialize(this)
        dev = DevHooksFactory.create(this)
        dev.buttons().forEach { (label, f) -> ui.addView(Button(this).apply { text = label; setOnClickListener { f() } }) }

        invocations = Wearables.startVoiceInvocationsStream(AutoDeviceSelector()).also { s ->
            lifecycleScope.launch {
                s.invocations.collect { inv ->
                    when (inv) { is LaunchApp -> { setStatus("Hey Meta → Glance"); inv.responseHandle.sendSuccess(null) } }
                }
            }
        }
        if (isVoiceInvocationsIntent(intent)) setStatus("Launched by voice")
        startLoop()
    }

    private fun startLoop() {
        if (GlanceGraph.controller != null) { setStatus("Loop already running"); return }
        lifecycleScope.launch(Dispatchers.Default) {
            try {
                val selector = dev.prepareDevice() ?: AutoDeviceSelector(filter = { it.isDisplayCapable() })
                GlanceGraph.start(applicationContext, lifecycleScope, selector)
                setStatus("Loop running. Debug: adb forward tcp:9000 tcp:9000 → http://127.0.0.1:9000/")
            } catch (e: Throwable) {
                Log.e("Glance", "start failed", e); setStatus("Start failed: ${e.message}")
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        if (isVoiceInvocationsIntent(intent)) setStatus("Foregrounded by voice")
    }

    private fun setStatus(s: String) { Log.i("Glance", s); runOnUiThread { status.text = s } }

    override fun onDestroy() { invocations?.close(); if (isFinishing) dev.stop(); super.onDestroy() }
}
