package glance.app

import android.app.Activity
import com.meta.wearable.dat.core.selectors.DeviceSelector

/**
 * Build-type seam. src/debug provides Mock Device Kit wiring + debug buttons;
 * src/release provides a no-op, so release builds never reference mwdat-mockdevice (debugImplementation only).
 */
interface DevHooks {
    /** Debug: pairs mock RBD and returns its selector once CONNECTED. Release: null (use real glasses). */
    suspend fun prepareDevice(): DeviceSelector?
    fun buttons(): List<Pair<String, () -> Unit>>
    fun stop()
}
