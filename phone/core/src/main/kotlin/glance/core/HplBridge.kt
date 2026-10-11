package glance.core

import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/*
 * Producer side of the HP Lifestyle (HPL) glasses bridge. Contract: heartypatch-lifestyle docs/m5-glasses.md,
 * Spec/hpl.event.v1 + Spec/hpl.signed_event.v1, reference implementation scripts/hpl_event_sign.py
 * (vendored here as tools/hpl/hpl_event_sign.py). Pure Kotlin/JVM: no Android, no network.
 *
 *   pairing   hplpair://v1?id=<16 [0-9a-z]>&k=<base64url 32-byte secret>   (shown once by HPL as QR / link)
 *   event     hpl.event.v1 `meal.logged`, deterministic ULID event_id → re-exports dedupe in HPL
 *   wrapper   {"spec":"hpl.signed_event.v1","pairing_id","ts","sig","body"}
 *             sig = hex(HMAC-SHA256(secret, "hpl.signed_event.v1\n" + pairing_id + "\n" + ts + "\n" + body))
 *   file      .hplevent = UTF-8 JSON Lines of wrappers (≤ 1,000 lines, ≤ 1 MB, body ≤ 16 KB)
 */

class HplPairing(val id: String, secret: ByteArray) {
    private val key = secret.copyOf()
    init {
        require(ID.matches(id)) { "pairing id must be 16 chars [0-9a-z]" }
        require(key.size == 32) { "secret must be 32 bytes" }
    }
    fun secret(): ByteArray = key.copyOf()
    /** Short non-secret fingerprint for the UI (first 8 hex of SHA-256(secret)), so both apps can be compared by eye. */
    fun fingerprint(): String = Hpl.hex(MessageDigest.getInstance("SHA-256").digest(key)).take(8)
    override fun toString() = "HplPairing($id, fp=${fingerprint()})" // never print the secret

    companion object {
        private val ID = Regex("^[0-9a-z]{16}$")

        /** Parses an HPL pairing link. Accepts surrounding whitespace (pasted text). Throws IllegalArgumentException. */
        fun parse(uri: String): HplPairing {
            val s = uri.trim()
            val prefix = "hplpair://v1?"
            require(s.startsWith(prefix, ignoreCase = true)) { "not an HP Lifestyle pairing link (expected hplpair://v1?…)" }
            val q = s.substring(prefix.length).split('&').mapNotNull {
                val i = it.indexOf('='); if (i <= 0) null else it.substring(0, i) to java.net.URLDecoder.decode(it.substring(i + 1), "UTF-8")
            }.toMap()
            val id = q["id"] ?: throw IllegalArgumentException("pairing link has no id")
            val k = q["k"] ?: throw IllegalArgumentException("pairing link has no key")
            val secret = try { Base64.getUrlDecoder().decode(k.trimEnd('=')) } catch (e: IllegalArgumentException) {
                throw IllegalArgumentException("pairing key is not base64url")
            }
            return HplPairing(id, secret)
        }
    }
}

object Hpl {
    const val WRAPPER_SPEC = "hpl.signed_event.v1"
    const val EVENT_SPEC = "hpl.event.v1"
    const val MIME = "application/x-hplevent"
    const val MAX_LINES = 1000
    const val MAX_FILE_BYTES = 1_000_000
    const val MAX_BODY_BYTES = 16 * 1024
    private const val CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private val TZ = Regex("^[A-Za-z_]+(/[A-Za-z0-9_+\\-]+)*$")
    private val ISO = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

    fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    fun sha256(s: String): ByteArray = MessageDigest.getInstance("SHA-256").digest(s.toByteArray(Charsets.UTF_8))

    fun hmacSha256(key: ByteArray, msg: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(msg) }

    /** ULID (Crockford base32, 26 chars) from a ms timestamp + first 10 bytes of entropy. Mirrors hpl_event_sign.ulid. */
    fun ulid(ms: Long, entropy: ByteArray): String {
        var n = java.math.BigInteger.valueOf(ms).shiftLeft(80).or(java.math.BigInteger(1, entropy.copyOf(10)))
        val out = CharArray(26)
        for (i in 25 downTo 0) { out[i] = CROCKFORD[n.and(java.math.BigInteger.valueOf(31)).toInt()]; n = n.shiftRight(5) }
        return String(out)
    }

    /** JSON string literal, escaping like Python json.dumps(ensure_ascii=False). */
    fun jstr(s: String): String {
        val b = StringBuilder(s.length + 2).append('"')
        for (c in s) when (c) {
            '"' -> b.append("\\\""); '\\' -> b.append("\\\\")
            '\n' -> b.append("\\n"); '\r' -> b.append("\\r"); '\t' -> b.append("\\t")
            '\b' -> b.append("\\b"); '\u000C' -> b.append("\\f")
            else -> if (c < ' ') b.append("\\u%04x".format(c.code)) else b.append(c)
        }
        return b.append('"').toString()
    }

    /** IANA zone if it matches the event schema, else "UTC" (e.g. raw offsets like GMT+05:30). */
    fun schemaTz(zoneId: String): String = if (TZ.matches(zoneId)) zoneId else "UTC"

    private fun truncateCodePoints(s: String, max: Int): String {
        val n = s.codePointCount(0, s.length)
        return if (n <= max) s else s.substring(0, s.offsetByCodePoints(0, max))
    }

    /** event_id = ULID(time = tsMs, entropy = SHA-256("glance|{tsMs}|{frameId}|{name}")[0:10]) — docs/m5-glasses.md §1. */
    fun eventId(entry: MealEntry, frameId: String): String =
        ulid(entry.tsMs, sha256("glance|${entry.tsMs}|$frameId|${entry.name}"))

    /**
     * Glance MealEntry → exact hpl.event.v1 `meal.logged` body (compact, key order identical to the Python reference).
     * frame, rawJson and photos are deliberately NOT sent: they stay in Glance.
     */
    fun mealLoggedBody(entry: MealEntry, frameId: String, tz: String, version: String): String {
        val name = truncateCodePoints(entry.name.trim(), 80)
        require(name.isNotEmpty()) { "meal name is empty" }
        val item = buildString {
            append("{\"name\":").append(jstr(name))
            entry.kcal?.let { append(",\"kcal_est\":").append(it.coerceAtLeast(0)) }
            entry.proteinG?.let { append(",\"protein_g\":").append(it.coerceAtLeast(0)) }
            append('}')
        }
        return "{\"spec\":\"$EVENT_SPEC\",\"event_id\":\"${eventId(entry, frameId)}\",\"type\":\"meal.logged\"," +
            "\"occurred_at\":\"${ISO.format(Instant.ofEpochMilli(entry.tsMs))}\",\"tz\":${jstr(schemaTz(tz))}," +
            "\"producer\":{\"name\":\"glance\",\"version\":${jstr(version.take(32))},\"processing\":\"on_device\"}," +
            "\"payload\":{\"items\":[$item]}}"
    }

    fun signature(pairing: HplPairing, ts: Long, body: String): String =
        hex(hmacSha256(pairing.secret(), "$WRAPPER_SPEC\n${pairing.id}\n$ts\n$body".toByteArray(Charsets.UTF_8)))

    /** One hpl.signed_event.v1 JSON line (no trailing newline). */
    fun signedLine(pairing: HplPairing, ts: Long, body: String): String {
        require(body.toByteArray(Charsets.UTF_8).size <= MAX_BODY_BYTES) { "event body > 16 KB" }
        return "{\"spec\":\"$WRAPPER_SPEC\",\"pairing_id\":\"${pairing.id}\",\"ts\":$ts," +
            "\"sig\":\"${signature(pairing, ts, body)}\",\"body\":${jstr(body)}}"
    }

    /** Constant-time check of a wrapper's signature (used by tests; HPL is the real verifier). */
    fun verify(pairing: HplPairing, ts: Long, body: String, sig: String): Boolean =
        MessageDigest.isEqual(signature(pairing, ts, body).toByteArray(), sig.toByteArray())

    /**
     * Builds one or more .hplevent file contents (JSON Lines, trailing newline) for [meals], each ≤ 1,000 lines / ≤ 1 MB.
     * [frameIdOf] supplies the stable frame id used in the deterministic event_id.
     */
    fun exportFiles(
        meals: List<MealEntry>, pairing: HplPairing, tz: String, version: String, nowSec: Long,
        frameIdOf: (MealEntry) -> String = { "t${it.frameTimeMs}" },
    ): List<String> {
        val files = mutableListOf<String>()
        val cur = StringBuilder(); var lines = 0
        for (m in meals.sortedBy { it.tsMs }) {
            val line = signedLine(pairing, nowSec, mealLoggedBody(m, frameIdOf(m), tz, version)) + "\n"
            val size = line.toByteArray(Charsets.UTF_8).size
            if (lines > 0 && (lines >= MAX_LINES || cur.toString().toByteArray(Charsets.UTF_8).size + size > MAX_FILE_BYTES)) {
                files += cur.toString(); cur.setLength(0); lines = 0
            }
            cur.append(line); lines++
        }
        if (lines > 0) files += cur.toString()
        return files
    }
}

/**
 * Persistent meal log (replaces the in-memory M2 placeholder until Room lands in Glance M4).
 * One line per meal: id \t tsMs \t frameTimeMs \t kcal \t proteinG \t status \t b64(name) \t b64(rawJson).
 * Lives in app-private storage (allowBackup=false). Status: NEW → EXPORTED (sent to HPL) | DISCARDED ("not a meal").
 */
class FileMealStore(private val file: File) : MealLog {
    enum class Status { NEW, EXPORTED, DISCARDED }
    data class Row(val id: Long, val entry: MealEntry, val status: Status)

    private val rows = mutableListOf<Row>()
    private val b64e = Base64.getUrlEncoder().withoutPadding()
    private val b64d = Base64.getUrlDecoder()

    init { load() }

    @Synchronized override fun insert(entry: MealEntry): Int {
        val id = (rows.maxOfOrNull { it.id } ?: 0) + 1
        rows += Row(id, entry, Status.NEW)
        file.parentFile?.mkdirs()
        file.appendText(encode(rows.last()) + "\n")
        return rows.count { it.status != Status.DISCARDED }
    }

    @Synchronized fun all(): List<Row> = rows.toList()
    @Synchronized fun visible(): List<Row> = rows.filter { it.status != Status.DISCARDED }.sortedByDescending { it.entry.tsMs }
    @Synchronized fun setStatus(ids: Collection<Long>, status: Status) {
        val set = ids.toSet()
        for (i in rows.indices) if (rows[i].id in set) rows[i] = rows[i].copy(status = status)
        persist()
    }

    private fun encode(r: Row) = listOf(
        r.id, r.entry.tsMs, r.entry.frameTimeMs, r.entry.kcal ?: "", r.entry.proteinG ?: "", r.status.name,
        b64e.encodeToString(r.entry.name.toByteArray()), b64e.encodeToString(r.entry.rawJson.toByteArray()),
    ).joinToString("\t")

    private fun decode(line: String): Row? = runCatching {
        val p = line.split('\t')
        Row(p[0].toLong(), MealEntry(p[1].toLong(), String(b64d.decode(p[6])), p[3].toIntOrNull(), p[4].toIntOrNull(),
            p[2].toLong(), String(b64d.decode(p[7]))), Status.valueOf(p[5]))
    }.getOrNull()

    private fun load() { if (file.exists()) file.readLines().forEach { l -> if (l.isNotBlank()) decode(l)?.let { rows += it } } }

    private fun persist() {
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.writeText(rows.joinToString("") { encode(it) + "\n" })
        if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
    }
}
