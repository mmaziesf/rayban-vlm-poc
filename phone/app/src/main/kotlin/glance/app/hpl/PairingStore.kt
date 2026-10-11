package glance.app.hpl

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import glance.core.HplPairing
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the one HP Lifestyle pairing (id + 32-byte HMAC secret). The secret is AES-GCM wrapped with a non-exportable
 * Android Keystore key and only the ciphertext sits in private prefs (allowBackup=false). Nothing is ever logged.
 */
class PairingStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("hpl_pairing", Context.MODE_PRIVATE)

    fun load(): HplPairing? = runCatching {
        val id = prefs.getString(K_ID, null) ?: return null
        val iv = Base64.decode(prefs.getString(K_IV, null) ?: return null, Base64.NO_WRAP)
        val ct = Base64.decode(prefs.getString(K_CT, null) ?: return null, Base64.NO_WRAP)
        val c = Cipher.getInstance(TRANSFORM).apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv)) }
        HplPairing(id, c.doFinal(ct))
    }.getOrNull()

    fun pairedAtMs(): Long = prefs.getLong(K_AT, 0)

    fun save(p: HplPairing) {
        val c = Cipher.getInstance(TRANSFORM).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val ct = c.doFinal(p.secret())
        prefs.edit()
            .putString(K_ID, p.id)
            .putString(K_IV, Base64.encodeToString(c.iv, Base64.NO_WRAP))
            .putString(K_CT, Base64.encodeToString(ct, Base64.NO_WRAP))
            .putLong(K_AT, System.currentTimeMillis())
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
        runCatching { KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(ALIAS) }
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build())
        }.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "hpl_pairing_wrap_v1"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val K_ID = "id"; const val K_IV = "iv"; const val K_CT = "ct"; const val K_AT = "paired_at"
    }
}
