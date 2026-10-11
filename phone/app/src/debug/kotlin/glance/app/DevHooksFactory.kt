package glance.app

import android.app.Activity
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.selectors.SpecificDeviceSelector
import glance.app.debug.DebugBus
import glance.app.debug.MockRig
import kotlinx.coroutines.launch

object DevHooksFactory {
    fun create(activity: Activity): DevHooks = object : DevHooks {
        private val mock = MockRig(activity).also { DebugBus.mock = it }
        private val scope = (activity as LifecycleOwner).lifecycleScope

        override suspend fun prepareDevice(): DeviceSelector {
            val id = mock.startAndAwait()
            Log.i("GlanceDebug", "mock RBD connected: $id — adb forward tcp:9000 tcp:9000 → http://127.0.0.1:9000/")
            return SpecificDeviceSelector(id)
        }

        override fun buttons(): List<Pair<String, () -> Unit>> = listOf(
            "Mock: say “what am I seeing?”" to { scope.launch { mock.say("what am I seeing") } },
            "Mock: say “log this meal”" to { scope.launch { mock.say("log this meal") } },
            "Mock: “Hey Meta, start Glance”" to { Log.i("GlanceDebug", "invocation=${mock.heyMetaStartGlance()}") },
        )

        override fun stop() = mock.stop()
    }
}
