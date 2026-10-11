package glance.app.log

import glance.core.MealEntry
import glance.core.MealLog

/** M2 placeholder. M4 replaces with Room (SQLite): meals(id, ts, name, kcal, protein_g, frame_path, raw_json, model_ver). */
class MemoryMealLog : MealLog {
    private val rows = mutableListOf<MealEntry>()
    @Synchronized override fun insert(entry: MealEntry): Int { rows += entry; return rows.size }
}
