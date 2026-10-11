package glance.app

import androidx.core.content.FileProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import glance.app.hpl.MealStoreHolder
import glance.app.hpl.PairingStore
import glance.core.Hpl
import glance.core.HplPairing
import glance.core.MealEntry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * HP Lifestyle bridge on a real Android runtime: Keystore-wrapped pairing, persistent meal store, FileProvider export.
 * Uses the PUBLIC test-only fixture pairing (fixturepair00001, secret bytes 1…32) so the written file can be checked
 * with heartypatch-lifestyle `scripts/hpl_event_sign.py verify` (tools/hpl/hpl_event_sign.py here).
 */
@RunWith(AndroidJUnit4::class)
class HplBridgeTest {
    private val ctx = InstrumentationRegistry.getInstrumentation().targetContext
    private val fixture = "hplpair://v1?id=fixturepair00001&k=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"

    @Test fun pairingRoundTripsThroughKeystore() {
        val store = PairingStore(ctx)
        val previous = store.load() // a real pairing on a dev phone must survive the test
        store.clear()
        assertNull(store.load())
        store.save(HplPairing.parse(fixture))
        val back = PairingStore(ctx).load()
        assertEquals("fixturepair00001", back?.id)
        assertArrayEquals(ByteArray(32) { (it + 1).toByte() }, back?.secret())
        val prefs = File(ctx.applicationInfo.dataDir, "shared_prefs/hpl_pairing.xml").readText()
        assertFalse("secret must not be stored in clear", prefs.contains("AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"))
        store.clear()
        assertNull(PairingStore(ctx).load())
        previous?.let { store.save(it) }
    }

    @Test fun exportWritesSignedFileReadableThroughFileProvider() {
        val pairing = HplPairing.parse(fixture)
        val meals = MealStoreHolder.get(ctx)
        val n0 = meals.all().size
        meals.insert(MealEntry(1_791_833_330_000, "chicken caesar salad", 470, 32, 1_791_833_329_500, "{\"is_food\":true}"))
        val row = meals.all().last()
        assertEquals(n0 + 1, meals.all().size)
        val text = Hpl.exportFiles(listOf(row.entry), pairing, "America/Los_Angeles", BuildConfig.VERSION_NAME, 1_791_833_400,
            frameIdOf = { "row${row.id}-t${it.frameTimeMs}" }).single()
        val dir = File(ctx.cacheDir, "hplevent").apply { mkdirs() }
        val f = File(dir, "test-export.hplevent").apply { writeText(text) }
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.hplfiles", f)
        assertEquals("content", uri.scheme)
        val read = ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes().toString(Charsets.UTF_8) }
        assertEquals(text, read)
        assertTrue(read.startsWith("{\"spec\":\"hpl.signed_event.v1\",\"pairing_id\":\"fixturepair00001\""))
        assertFalse("raw VLM output must not be exported", read.contains("is_food"))
        // Don't leave a synthetic meal in a real phone's log.
        meals.setStatus(listOf(row.id), glance.core.FileMealStore.Status.DISCARDED)
        f.delete()
    }
}
