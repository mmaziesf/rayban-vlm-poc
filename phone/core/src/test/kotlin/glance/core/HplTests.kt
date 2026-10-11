package glance.core

import java.io.File
import java.time.Instant

/** HP Lifestyle bridge contract tests. Expected strings come from heartypatch-lifestyle scripts/hpl_event_sign.py. */
fun hplTests(check: (String, Boolean, Any?) -> Unit) {
    val fixtureUri = "hplpair://v1?id=fixturepair00001&k=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
    val p = HplPairing.parse("  $fixtureUri\n")
    check("hpl: parse fixture pairing", p.id == "fixturepair00001" && p.secret().contentEquals(ByteArray(32) { (it + 1).toByte() }), p)
    check("hpl: toString hides secret", !p.toString().contains("AQID"), p)
    for (bad in listOf("https://v1?id=fixturepair00001&k=AQ", "hplpair://v1?id=SHORT&k=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA",
                       "hplpair://v1?id=fixturepair00001&k=AQID", "hplpair://v1?id=fixturepair00001", "hplpair://v1?id=fixturepair00001&k=!!!"))
        check("hpl: reject pairing '$bad'", runCatching { HplPairing.parse(bad) }.isFailure, null)

    // RFC 4231 test case 2
    check("hpl: HMAC RFC4231 #2", Hpl.hex(Hpl.hmacSha256("Jefe".toByteArray(), "what do ya want for nothing?".toByteArray())) ==
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", null)

    val ts = Instant.parse("2026-10-11T19:42:10Z").toEpochMilli()
    val entry = MealEntry(ts, "chicken caesar salad", 470, 32, ts, "{}")
    val body = Hpl.mealLoggedBody(entry, "buf-000123", "America/Los_Angeles", "0.1.0-fixture")
    val wantBody = """{"spec":"hpl.event.v1","event_id":"01M4P7SAJGANKTHYVGBT9W1TXP","type":"meal.logged","occurred_at":"2026-10-11T19:42:10Z","tz":"America/Los_Angeles","producer":{"name":"glance","version":"0.1.0-fixture","processing":"on_device"},"payload":{"items":[{"name":"chicken caesar salad","kcal_est":470,"protein_g":32}]}}"""
    check("hpl: body == Python reference (fixture 07)", body == wantBody, body)
    val line = Hpl.signedLine(p, 1791756900, body)
    val wantLine = """{"spec":"hpl.signed_event.v1","pairing_id":"fixturepair00001","ts":1791756900,"sig":"57aab7eeae10a824d41439411a439f794675a30d410cef6bce11c3d051f9e275","body":"{\"spec\":\"hpl.event.v1\",\"event_id\":\"01M4P7SAJGANKTHYVGBT9W1TXP\",\"type\":\"meal.logged\",\"occurred_at\":\"2026-10-11T19:42:10Z\",\"tz\":\"America/Los_Angeles\",\"producer\":{\"name\":\"glance\",\"version\":\"0.1.0-fixture\",\"processing\":\"on_device\"},\"payload\":{\"items\":[{\"name\":\"chicken caesar salad\",\"kcal_est\":470,\"protein_g\":32}]}}"}"""
    check("hpl: signed line == Fixtures/signed/01-glance-meal", line == wantLine, line)
    check("hpl: verify ok", Hpl.verify(p, 1791756900, body, "57aab7eeae10a824d41439411a439f794675a30d410cef6bce11c3d051f9e275"), null)
    check("hpl: verify rejects tampered body", !Hpl.verify(p, 1791756900, body.replace("470", "47"), "57aab7eeae10a824d41439411a439f794675a30d410cef6bce11c3d051f9e275"), null)

    // Escaping + optional fields + tz fallback, against Python json.dumps(ensure_ascii=False)
    val t2 = Instant.parse("2026-10-11T08:00:00Z").toEpochMilli()
    val odd = Hpl.mealLoggedBody(MealEntry(t2, "café \"bowl\"\n\\ x", null, null, t2, ""), "t1", "UTC", "1")
    val wantOdd = """{"spec":"hpl.event.v1","event_id":"01M4MZKM0084EZQCJ4H6DKBSW8","type":"meal.logged","occurred_at":"2026-10-11T08:00:00Z","tz":"UTC","producer":{"name":"glance","version":"1","processing":"on_device"},"payload":{"items":[{"name":"café \"bowl\"\n\\ x"}]}}"""
    check("hpl: escaping + no kcal == Python", odd == wantOdd, odd)
    check("hpl: tz fallback for raw offsets", Hpl.schemaTz("GMT+05:30") == "UTC" && Hpl.schemaTz("Asia/Kolkata") == "Asia/Kolkata", null)
    check("hpl: name capped at 80 code points", Hpl.mealLoggedBody(entry.copy(name = "😀".repeat(100)), "f", "UTC", "1").contains("\"" + "😀".repeat(80) + "\""), null)
    check("hpl: no rawJson/frame in body", !Hpl.mealLoggedBody(entry.copy(rawJson = "{\"secret\":1}"), "buf-000123", "UTC", "1").contains("secret"), null)
    check("hpl: event id deterministic", Hpl.eventId(entry, "x") == Hpl.eventId(entry, "x") && Hpl.eventId(entry, "x") != Hpl.eventId(entry, "y"), null)

    // Export files: JSON Lines, chunked at 1,000 lines
    val many = (0 until 1001).map { MealEntry(ts + it * 1000L, "meal $it", it, null, ts, "") }
    val files = Hpl.exportFiles(many, p, "UTC", "1", 1791756900)
    check("hpl: export chunks 1001 → 1000 + 1", files.size == 2 && files[0].lines().filter { it.isNotEmpty() }.size == 1000 && files[1].lines().filter { it.isNotEmpty() }.size == 1, files.map { it.length })
    check("hpl: export ≤ 1 MB per file", files.all { it.toByteArray().size <= Hpl.MAX_FILE_BYTES }, null)
    check("hpl: export one meal = one line", Hpl.exportFiles(listOf(entry), p, "UTC", "1", 1)[0].count { it == '\n' } == 1, null)

    // Contract artifact for CI: python3 tools/hpl/hpl_event_sign.py verify $HPL_CONTRACT_OUT (fixture pairing)
    System.getenv("HPL_CONTRACT_OUT")?.let { out ->
        val sample = listOf(entry, entry.copy(tsMs = ts + 3_600_000, name = "café \"bowl\" ✓", kcal = null), entry.copy(tsMs = ts + 7_200_000, proteinG = null))
        File(out).apply { parentFile?.mkdirs() }.writeText(Hpl.exportFiles(sample, p, "America/Los_Angeles", "ci", System.currentTimeMillis() / 1000).single())
        check("hpl: wrote contract file", File(out).length() > 0, out)
    }

    // Persistent store
    val f = File.createTempFile("meals", ".tsv").also { it.delete() }
    val s = FileMealStore(f)
    s.insert(entry); s.insert(entry.copy(name = "tab\there", tsMs = ts + 1)); s.insert(entry.copy(name = "not food", tsMs = ts + 2))
    s.setStatus(listOf(3L), FileMealStore.Status.DISCARDED); s.setStatus(listOf(1L), FileMealStore.Status.EXPORTED)
    val s2 = FileMealStore(f)
    check("hpl: store survives reopen", s2.all().size == 3 && s2.visible().size == 2, s2.all())
    check("hpl: store keeps status + odd names", s2.all().first { it.id == 1L }.status == FileMealStore.Status.EXPORTED &&
        s2.all().first { it.id == 2L }.entry.name == "tab\there" && s2.all().first { it.id == 2L }.status == FileMealStore.Status.NEW, s2.all())
    check("hpl: new ids continue after reopen", s2.insert(entry) == 3 && s2.all().last().id == 4L, s2.all())
    f.delete()
}
