import Foundation

public enum Prompts {
    public static let describe = "You are a heads-up assistant. In at most two short sentences, say what the wearer is looking at. " +
        "Mention anything safety-relevant first. No preamble."
    public static let meal = "If this image shows food, reply with ONLY a JSON object: " +
        "{\"is_food\":true,\"name\":\"short dish name\",\"kcal\":integer,\"protein_g\":integer}. " +
        "If it does not show food reply {\"is_food\":false}."
}

/// Tolerant extractor for the meal JSON (same behaviour as Kotlin MealParser).
public enum MealParser {
    private static let obj = Rx(#"\{[^{}]*\}"#)
    private static func str(_ j: String, _ k: String) -> String? { Rx("\"\(k)\"\\s*:\\s*\"([^\"]*)\"").firstGroup(j) }
    private static func int(_ j: String, _ k: String) -> Int? { Rx("\"\(k)\"\\s*:\\s*(\\d+)").firstGroup(j).flatMap(Int.init) }
    private static func bool(_ j: String, _ k: String) -> String? { Rx("\"\(k)\"\\s*:\\s*(true|false)").firstGroup(j) }

    public static func parse(_ raw: String, nowMs: Int64, frameTimeMs: Int64) -> MealEntry? {
        guard let json = obj.firstGroup(raw, 0), bool(json, "is_food") == "true",
              let name = str(json, "name"), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return MealEntry(tsMs: nowMs, name: name, kcal: int(json, "kcal"), proteinG: int(json, "protein_g"),
                         frameTimeMs: frameTimeMs, rawJson: json)
    }
}
