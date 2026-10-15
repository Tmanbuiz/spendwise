package com.spendwise.spendwise

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64

/**
 * The single point of contact between the notification listener service and
 * Flutter.
 *
 * The hard constraint this class exists to satisfy: **Android runs the
 * notification listener without the app's UI.** It binds the service at boot,
 * or on demand, long before MainActivity exists and long after it is gone. A
 * purchase alert almost always arrives while the user is in their banking app
 * or a shop — never while staring at SpendWise.
 *
 * So neither the watched-package list nor the captured notifications may live
 * only in memory. Both are persisted:
 *
 *  * **Watched packages** are written when the user picks their banks and read
 *    back by the service on connect, so filtering works in a fresh process.
 *  * **Captured notifications** are appended to a bounded on-disk queue when no
 *    Flutter engine is attached, and drained the next time the app opens.
 *
 * The queue is bounded rather than unbounded — a background service must not
 * grow without limit — but bounded is very different from dropping, which is
 * what this class used to do.
 */
object NotificationBridge {

    private const val PREFS = "spendwise_capture"
    private const val KEY_PACKAGES = "watched_packages"
    private const val KEY_QUEUE = "pending_notifications"
    private const val KEY_SEEN = "stat_seen"
    private const val KEY_MATCHED = "stat_matched"
    private const val KEY_QUEUED = "stat_queued"
    private const val KEY_DELIVERED = "stat_delivered"

    /** Oldest entries are discarded past this. Roughly a month of alerts. */
    private const val MAX_QUEUE = 2000
    private const val KEY_DROPPED = "stat_dropped"
    private const val KEY_DEAD = "dead_notifications"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var listenerConnected: Boolean = false

    @Volatile
    private var prefs: SharedPreferences? = null

    /**
     * The live listener service, when Android has one bound.
     *
     * Held so the UI can ask for a re-scan of notifications already sitting in
     * the shade. Cleared on disconnect so a dead service is never called.
     */
    @Volatile
    private var service: SpendWiseNotificationListenerService? = null

    fun setService(instance: SpendWiseNotificationListenerService?) {
        service = instance
    }

    /** Re-reads currently posted notifications. Returns false if unavailable. */
    fun rescanActive(): Boolean {
        val live = service ?: return false
        live.scanActive()
        return true
    }

    /**
     * Must be called from both the service and the activity, because either
     * may be the first component Android creates.
     */
    fun attach(context: Context) {
        if (prefs == null) {
            synchronized(lock) {
                if (prefs == null) {
                    prefs = context.applicationContext
                        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                }
            }
        }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun setListenerConnected(connected: Boolean) {
        listenerConnected = connected
    }

    fun isListenerConnected(): Boolean = listenerConnected

    /** Persisted so a service-only process still filters correctly. */
    fun setWatchedPackages(packages: Set<String>) {
        prefs?.edit()?.putStringSet(KEY_PACKAGES, packages)?.apply()
    }

    fun watchedPackages(): Set<String> =
        prefs?.getStringSet(KEY_PACKAGES, emptySet()) ?: emptySet()

    fun isWatchedPackage(packageName: String): Boolean =
        watchedPackages().contains(packageName)

    /**
     * Records one notification.
     *
     * Delivered live when the app is open, and queued to disk when it is not.
     * Queuing is the path that actually matters: it is the one that runs when
     * the user taps their card in a shop.
     */
    fun dispatch(
        packageName: String,
        title: String,
        body: String,
        subText: String,
        postedAt: Long,
    ) {
        bump(KEY_MATCHED)

        val payload = mapOf(
            "envelopeId" to UUID.randomUUID().toString(),
            "packageName" to packageName,
            "title" to title,
            "body" to body,
            "subText" to subText,
            "postedAt" to postedAt,
        )

        enqueue(payload)
        val sink = eventSink
        if (sink != null) {
            // EventSink must be touched on the main thread; onNotificationPosted
            // is not guaranteed to run there.
            mainHandler.post {
                try {
                    sink.success(payload)
                    bump(KEY_DELIVERED)
                } catch (_: IllegalStateException) {
                    // Engine detached between the null check and here; the
                    // queue is the fallback so nothing is lost.
                    // Already persisted before live delivery.
                }
            }
            return
        }

    }

    private fun enqueue(payload: Map<String, Any>) {
        if (prefs == null) return
        synchronized(lock) {
            val existing = loadQueue(KEY_QUEUE)
            val next = JSONArray()

            // Keep the newest MAX_QUEUE entries.
            val start = maxOf(0, existing.length() - (MAX_QUEUE - 1))
            for (i in start until existing.length()) {
                next.put(existing.get(i))
            }

            next.put(JSONObject(payload as Map<*, *>))
            if (existing.length() >= MAX_QUEUE) bump(KEY_DROPPED)
            saveQueue(KEY_QUEUE, next)
        }
        bump(KEY_QUEUED)
    }

    /**
     * Returns a durable snapshot. Only an explicit acknowledgement removes
     * an entry, so process death during ingestion leaves it retryable.
     */
    fun drainQueue(): List<Map<String, Any?>> {
        if (prefs == null) return emptyList()
        synchronized(lock) {
            val array = loadQueue(KEY_QUEUE)
            // Assign IDs to legacy envelopes before exposing them.
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                if (!item.has("envelopeId")) item.put("envelopeId", UUID.randomUUID().toString())
            }
            saveQueue(KEY_QUEUE, array)
            val out = ArrayList<Map<String, Any?>>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
                        "envelopeId" to item.optString("envelopeId"),
                        "packageName" to item.optString("packageName"),
                        "title" to item.optString("title"),
                        "body" to item.optString("body"),
                        "subText" to item.optString("subText"),
                        "postedAt" to item.optLong("postedAt"),
                    )
                )
            }
            return out
        }
    }

    fun acknowledge(id: String, failed: Boolean = false) {
        synchronized(lock) {
            val queue = loadQueue(KEY_QUEUE)
            val next = JSONArray()
            val dead = loadQueue(KEY_DEAD)
            for (i in 0 until queue.length()) {
                val item = queue.optJSONObject(i) ?: continue
                if (item.optString("envelopeId") != id) { next.put(item); continue }
                if (failed) {
                    val retries = item.optInt("retries") + 1
                    item.put("retries", retries).put("lastFailure", "ingest_failed")
                    if (retries < 5) next.put(item) else dead.put(item)
                }
            }
            while (dead.length() > 100) { dead.remove(0); bump(KEY_DROPPED) }
            // Persist failed records first, so a crash cannot silently lose one.
            saveQueue(KEY_DEAD, dead)
            saveQueue(KEY_QUEUE, next)
        }
    }

    private fun queueKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = "spendwise.capture.v1"
        val existing = ks.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun loadQueue(key: String): JSONArray {
        val raw = prefs?.getString(key, null) ?: return JSONArray()
        if (raw.startsWith("[")) return JSONArray(raw) // legacy migration on next write
        val payload = JSONObject(raw)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, queueKey(), GCMParameterSpec(128, Base64.decode(payload.getString("iv"), Base64.NO_WRAP)))
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        return JSONArray(String(cipher.doFinal(Base64.decode(payload.getString("data"), Base64.NO_WRAP)), Charsets.UTF_8))
    }
    private fun saveQueue(key: String, value: JSONArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, queueKey())
        cipher.updateAAD(key.toByteArray(Charsets.UTF_8))
        val payload = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("data", Base64.encodeToString(cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
        check(prefs?.edit()?.putString(key, payload.toString())?.commit() == true) { "Queue persistence failed" }
    }

    fun pendingCount(): Int {
        if (prefs == null) return 0
        return try {
            loadQueue(KEY_QUEUE).length()
        } catch (_: Exception) {
            0
        }
    }

    /** Counters that make the capture path observable end to end. */
    fun stats(): Map<String, Any> = mapOf(
        "seen" to read(KEY_SEEN),
        "matched" to read(KEY_MATCHED),
        "queued" to read(KEY_QUEUED),
        "delivered" to read(KEY_DELIVERED),
        "pending" to pendingCount(),
        "dropped" to read(KEY_DROPPED),
        "failed" to loadQueue(KEY_DEAD).length(),
        "listenerConnected" to listenerConnected,
        "watchedPackages" to watchedPackages().toList(),
    )

    fun countSeen() = bump(KEY_SEEN)

    fun resetStats() {
        prefs?.edit()
            ?.putInt(KEY_SEEN, 0)
            ?.putInt(KEY_MATCHED, 0)
            ?.putInt(KEY_QUEUED, 0)
            ?.putInt(KEY_DELIVERED, 0)
            ?.apply()
    }

    private fun read(key: String): Int = prefs?.getInt(key, 0) ?: 0

    private fun bump(key: String) {
        val store = prefs ?: return
        synchronized(lock) {
            store.edit().putInt(key, store.getInt(key, 0) + 1).apply()
        }
    }
}
