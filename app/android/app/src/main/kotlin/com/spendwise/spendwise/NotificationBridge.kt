package com.spendwise.spendwise

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

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
    private const val MAX_QUEUE = 200

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
            "packageName" to packageName,
            "title" to title,
            "body" to body,
            "subText" to subText,
            "postedAt" to postedAt,
        )

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
                    enqueue(payload)
                }
            }
            return
        }

        enqueue(payload)
    }

    private fun enqueue(payload: Map<String, Any>) {
        val store = prefs ?: return
        synchronized(lock) {
            val existing = JSONArray(store.getString(KEY_QUEUE, "[]") ?: "[]")
            val next = JSONArray()

            // Keep the newest MAX_QUEUE entries.
            val start = maxOf(0, existing.length() - (MAX_QUEUE - 1))
            for (i in start until existing.length()) {
                next.put(existing.get(i))
            }

            next.put(JSONObject(payload as Map<*, *>))
            store.edit().putString(KEY_QUEUE, next.toString()).apply()
        }
        bump(KEY_QUEUED)
    }

    /**
     * Returns everything queued and clears it.
     *
     * Read-and-clear in one locked step so a notification arriving mid-drain
     * is either fully included or left for the next drain, never lost between
     * the two.
     */
    fun drainQueue(): List<Map<String, Any?>> {
        val store = prefs ?: return emptyList()
        synchronized(lock) {
            val raw = store.getString(KEY_QUEUE, "[]") ?: "[]"
            store.edit().putString(KEY_QUEUE, "[]").apply()

            val array = JSONArray(raw)
            val out = ArrayList<Map<String, Any?>>(array.length())
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
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

    fun pendingCount(): Int {
        val store = prefs ?: return 0
        return try {
            JSONArray(store.getString(KEY_QUEUE, "[]") ?: "[]").length()
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
