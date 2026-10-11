package glance.app.hpl

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.text.format.DateFormat
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.core.content.FileProvider
import glance.app.BuildConfig
import glance.core.FileMealStore
import glance.core.FileMealStore.Status
import glance.core.Hpl
import glance.core.HplPairing
import java.io.File
import java.time.ZoneId
import java.util.Date

/**
 * "HP Lifestyle" screen: pair with HP Lifestyle (paste the hplpair:// link, or open it from the QR / share link),
 * review logged meals, and share the ones you confirm as a signed .hplevent file. Fully offline: the file goes
 * through the Android share sheet (Drive, Files, Signal, USB, …); Glance itself opens no socket.
 * Contract: heartypatch-lifestyle docs/m5-glasses.md.
 */
class HplActivity : ComponentActivity() {
    private lateinit var pairings: PairingStore
    private lateinit var meals: FileMealStore
    private lateinit var root: LinearLayout
    private val selected = mutableSetOf<Long>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "HP Lifestyle"
        pairings = PairingStore(this)
        meals = MealStoreHolder.get(this)
        root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(40, 40, 40, 40) }
        setContentView(ScrollView(this).apply { addView(root) })
        meals.visible().filter { it.status == Status.NEW }.forEach { selected += it.id }
        render()
        handleLink(intent)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); handleLink(intent) }

    /** hplpair://v1?… opened from HP Lifestyle's QR (via a QR reader) or share link. Always asks before pairing. */
    private fun handleLink(i: Intent?) {
        val uri = i?.data?.toString() ?: return
        if (i.action != Intent.ACTION_VIEW || !uri.startsWith("hplpair:", ignoreCase = true)) return
        i.data = null
        confirmPair(uri)
    }

    private fun confirmPair(uri: String) {
        val p = try { HplPairing.parse(uri) } catch (e: IllegalArgumentException) { toast(e.message ?: "Invalid link"); return }
        val replacing = pairings.load()?.let { "\n\nThis replaces the current pairing (${it.fingerprint()})." } ?: ""
        AlertDialog.Builder(this)
            .setTitle("Pair with HP Lifestyle?")
            .setMessage("Glance will sign meal exports for this HP Lifestyle app.\n\nCode: ${p.fingerprint()}  " +
                "(check it matches HP Lifestyle).$replacing\n\nOnly pair a link you got from your own HP Lifestyle app.")
            .setPositiveButton("Pair") { _, _ -> pairings.save(p); toast("Paired"); render() }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun render() {
        root.removeAllViews()
        val p = pairings.load()
        header("Pairing")
        if (p == null) {
            text("Not paired. In HP Lifestyle: Settings › Glasses meals › Pair a companion. Scan its QR with your camera " +
                "and open the hplpair:// link, or copy the link and paste it here.")
            val field = EditText(this).apply { hint = "hplpair://v1?id=…&k=…"; setSingleLine() }
            root.addView(field, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            button("Pair with pasted link") {
                val t = field.text.toString().ifBlank { clipboardText() }
                if (t.isBlank()) toast("Paste the hplpair:// link first") else confirmPair(t)
            }
        } else {
            val at = pairings.pairedAtMs().takeIf { it > 0 }?.let { " · since " + DateFormat.getDateFormat(this).format(Date(it)) } ?: ""
            text("Paired · code ${p.fingerprint()}$at")
            button("Unpair") {
                AlertDialog.Builder(this).setMessage("Unpair from HP Lifestyle? The secret is deleted from this phone.")
                    .setPositiveButton("Unpair") { _, _ -> pairings.clear(); render() }.setNegativeButton("Cancel", null).show()
            }
        }

        header("Meals")
        val rows = meals.visible()
        if (rows.isEmpty()) text("No meals yet. Say \"Hey Meta, log this meal\" while looking at food.")
        text("Tick the meals that are right. Only ticked meals are sent. Names and calories are on-device estimates; " +
            "frames and raw model output never leave Glance.")
        for (r in rows) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            val label = buildString {
                append(DateFormat.format("EEE d MMM, HH:mm", r.entry.tsMs)).append(" · ").append(r.entry.name)
                r.entry.kcal?.let { append(" · ~$it kcal") }
                r.entry.proteinG?.let { append(" · ${it} g protein") }
                if (r.status == Status.EXPORTED) append(" · sent")
            }
            row.addView(CheckBox(this).apply {
                text = label; isChecked = r.id in selected
                setOnCheckedChangeListener { _, on -> if (on) selected += r.id else selected -= r.id }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(Button(this).apply {
                text = "Not a meal"
                setOnClickListener { meals.setStatus(listOf(r.id), Status.DISCARDED); selected -= r.id; render() }
            })
            root.addView(row)
        }
        button("Send ticked meals to HP Lifestyle") { export() }
    }

    private fun export() {
        val p = pairings.load() ?: return toast("Pair with HP Lifestyle first")
        val chosen = meals.visible().filter { it.id in selected }
        if (chosen.isEmpty()) return toast("Tick at least one meal")
        val tz = ZoneId.systemDefault().id
        val ids = java.util.IdentityHashMap<glance.core.MealEntry, Long>().apply { chosen.forEach { put(it.entry, it.id) } }
        val contents = Hpl.exportFiles(chosen.map { it.entry }, p, tz, BuildConfig.VERSION_NAME, System.currentTimeMillis() / 1000,
            frameIdOf = { "row${ids[it]}-t${it.frameTimeMs}" })
        val dir = File(cacheDir, "hplevent").apply { deleteRecursively(); mkdirs() } // only the latest export is kept
        val stamp = DateFormat.format("yyyy-MM-dd-HHmm", System.currentTimeMillis())
        val files = contents.mapIndexed { i, c ->
            File(dir, if (contents.size == 1) "glance-$stamp.hplevent" else "glance-$stamp-${i + 1}.hplevent").apply { writeText(c) }
        }
        val uris = files.map { FileProvider.getUriForFile(this, "$packageName.hplfiles", it) }
        val send = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
                   else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        send.type = Hpl.MIME
        send.clipData = ClipData.newRawUri("meals", uris[0]).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, "Send ${chosen.size} meal(s) to HP Lifestyle"))
        // Marked sent once handed to the share sheet; re-sending is harmless (deterministic event_id → HPL dedupes).
        meals.setStatus(chosen.map { it.id }, Status.EXPORTED)
        selected.clear()
        render()
    }

    private fun clipboardText(): String =
        (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip?.getItemAt(0)?.coerceToText(this)?.toString() ?: ""

    private fun header(s: String) = root.addView(TextView(this).apply { text = s; textSize = 20f; setPadding(0, 32, 0, 8) })
    private fun text(s: String) = root.addView(TextView(this).apply { text = s; setPadding(0, 4, 0, 4) })
    private fun button(s: String, f: () -> Unit) = root.addView(Button(this).apply { text = s; setOnClickListener { f() } })
    private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
