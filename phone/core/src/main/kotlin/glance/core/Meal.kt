package glance.core

object Prompts {
    const val DESCRIBE = "You are a heads-up assistant. In at most two short sentences, say what the wearer is looking at. " +
        "Mention anything safety-relevant first. No preamble."
    const val MEAL = "If this image shows food, reply with ONLY a JSON object: " +
        "{\"is_food\":true,\"name\":\"short dish name\",\"kcal\":integer,\"protein_g\":integer}. " +
        "If it does not show food reply {\"is_food\":false}."
}

/** Tiny tolerant extractor for the meal JSON (no JSON dependency in core). */
object MealParser {
    private fun str(json: String, key: String) = Regex("\"$key\"\\s*:\\s*\"([^\"]*)\"").find(json)?.groupValues?.get(1)
    private fun int(json: String, key: String) = Regex("\"$key\"\\s*:\\s*(\\d+)").find(json)?.groupValues?.get(1)?.toIntOrNull()
    private fun bool(json: String, key: String) = Regex("\"$key\"\\s*:\\s*(true|false)").find(json)?.groupValues?.get(1)

    fun parse(raw: String, nowMs: Long, frameTimeMs: Long): MealEntry? {
        val json = Regex("\\{[^{}]*\\}").find(raw)?.value ?: return null
        if (bool(json, "is_food") != "true") return null
        val name = str(json, "name")?.takeIf { it.isNotBlank() } ?: return null
        return MealEntry(nowMs, name, int(json, "kcal"), int(json, "protein_g"), frameTimeMs, json)
    }
}
