package glance.app.hpl

import android.content.Context
import glance.core.FileMealStore
import java.io.File

/** One persistent meal log per process, shared by the glasses loop (writer) and the HP Lifestyle screen (export). */
object MealStoreHolder {
    @Volatile private var store: FileMealStore? = null
    fun get(context: Context): FileMealStore = store ?: synchronized(this) {
        store ?: FileMealStore(File(context.applicationContext.filesDir, "meals/meals.tsv")).also { store = it }
    }
}
