package glance.app.vlm

import android.app.ActivityManager
import android.content.Context
import android.util.Log
import glance.app.BuildConfig
import glance.core.VlmEngine
import glance.core.VlmSelection
import java.io.File

/**
 * Chooses stub vs real (M1c). Inputs:
 *  - BuildConfig.VLM_MODE: `./gradlew assembleDebug -Pglance.vlm=real` (default "stub").
 *  - Debug-only launch override: `adb shell am start -n dev.arash.glance/glance.app.MainActivity --es vlm real`.
 * Model location (first existing wins), see docs/M1C_REAL_VLM.md:
 *  1. <getExternalFilesDir>/models/gemma-4-E4B-it.litertlm  = /sdcard/Android/data/dev.arash.glance/files/models/
 *     (adb push target; no storage permission needed; deleted on uninstall)
 *  2. <filesDir>/models/gemma-4-E4B-it.litertlm             (internal; copied there with `run-as` for debug builds)
 */
object VlmFactory {
    const val MODEL_FILE = "gemma-4-E4B-it.litertlm"
    const val MODEL_SIZE = 3_659_530_240L          // HF x-linked-size, 2026-10-10
    private const val TAG = "GlanceVlm"

    data class Built(val engine: VlmEngine, val decision: VlmSelection.Decision)

    fun candidates(ctx: Context): List<File> = listOfNotNull(
        ctx.getExternalFilesDir("models")?.let { File(it, MODEL_FILE) },
        File(File(ctx.filesDir, "models"), MODEL_FILE),
    )

    fun build(ctx: Context, override: String?): Built {
        val am = ctx.getSystemService(ActivityManager::class.java)
        val mi = ActivityManager.MemoryInfo().also { am?.getMemoryInfo(it) }
        val cands = candidates(ctx).map { VlmSelection.Candidate(it.absolutePath, it.isFile, if (it.isFile) it.length() else 0) }
        val d = VlmSelection.decide(BuildConfig.VLM_MODE, override, cands, MODEL_SIZE, mi.availMem.takeIf { it > 0 })
        Log.i(TAG, "mode=${d.mode} reason=\"${d.reason}\" build=${BuildConfig.VLM_MODE} override=$override availMemMB=${mi.availMem shr 20}")
        if (d.mode == VlmSelection.Mode.STUB) return Built(CannedVlmEngine(), d)
        return try {
            Built(LiteRtVlmEngine(d.modelPath!!, ctx.cacheDir.absolutePath), d)
        } catch (t: Throwable) {   // GPU delegate missing (emulator), OOM, corrupt file …
            Log.e(TAG, "real engine init failed → stub", t)
            Built(CannedVlmEngine(), VlmSelection.Decision(VlmSelection.Mode.STUB, null, "init failed: ${t.javaClass.simpleName}: ${t.message}"))
        }
    }
}
