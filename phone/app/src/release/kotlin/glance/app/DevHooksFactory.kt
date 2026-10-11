package glance.app

import android.app.Activity
import com.meta.wearable.dat.core.selectors.DeviceSelector

object DevHooksFactory {
    fun create(activity: Activity): DevHooks = object : DevHooks {
        override suspend fun prepareDevice(): DeviceSelector? = null
        override fun buttons(): List<Pair<String, () -> Unit>> = emptyList()
        override fun stop() {}
    }
}
