package com.spendwise.spendwise

import android.app.Notification
import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Captures notifications posted by the banking apps the user selected.
 *
 * Android starts and stops this service on its own schedule, and it routinely
 * runs while no Flutter engine exists — that is the normal case, not the edge
 * case, because purchase alerts arrive while the user is in a shop rather than
 * in SpendWise. So this service never assumes the UI is alive: it hands every
 * match to [NotificationBridge], which delivers it live if an engine happens
 * to be attached and persists it to disk otherwise.
 */
class SpendWiseNotificationListenerService : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        // Attach here rather than in onListenerConnected: Android may deliver
        // notifications before the connect callback lands, and without storage
        // attached those would be filtered out by an empty watch list.
        NotificationBridge.attach(this)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        NotificationBridge.attach(this)
        NotificationBridge.setService(this)
        NotificationBridge.setListenerConnected(true)

        // Alerts posted before access was granted — or before the app was
        // installed — are still sitting in the shade. Reading them on connect
        // means a user who sets SpendWise up after a purchase still sees it,
        // instead of having to spend again to prove the app works.
        scanActive()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        NotificationBridge.setService(null)
        NotificationBridge.setListenerConnected(false)

        // Ask the system to bind us again.
        //
        // Being disconnected is not a decision the user made. Android tears
        // the listener down under memory pressure, and Samsung's battery
        // management does it far more eagerly than stock Android — a device
        // that puts the app to sleep will disconnect it and never come back on
        // its own. Without this the service can stay dead until the app is
        // reopened or the phone reboots, and every purchase in between is
        // missed silently, which is the worst way for this app to fail.
        //
        // This cannot resurrect a listener the user revoked: the platform only
        // honours a rebind request while the component is still enabled in
        // Notification access, so a genuine revocation stays revoked.
        requestRebind(ComponentName(this, SpendWiseNotificationListenerService::class.java))
    }

    /**
     * Re-reads every notification currently posted.
     *
     * Safe to call repeatedly: the parser fingerprints each transaction and
     * the duplicate detector drops anything already recorded, so a re-scan
     * cannot double-count.
     */
    fun scanActive() {
        val active = try {
            activeNotifications
        } catch (_: SecurityException) {
            // Access revoked between the connect callback and here.
            return
        } ?: return

        for (notification in active) {
            handle(notification, countAsSeen = false)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        handle(sbn, countAsSeen = true)
    }

    private fun handle(sbn: StatusBarNotification?, countAsSeen: Boolean) {
        val notification = sbn ?: return
        val packageName = notification.packageName ?: return

        if (countAsSeen) NotificationBridge.countSeen()

        // Filtering by package here means notifications from apps the user did
        // not select are never read into memory at all. The watch list comes
        // from disk, so this works in a process Android started on its own.
        if (!NotificationBridge.isWatchedPackage(packageName)) return

        val extras = notification.notification?.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()

        // Banks routinely truncate EXTRA_TEXT and put the full sentence in
        // EXTRA_BIG_TEXT. The longer of the two is the one worth parsing.
        val text = if (bigText.length > body.length) bigText else body

        if (title.isBlank() && text.isBlank()) return

        NotificationBridge.dispatch(
            packageName = packageName,
            title = title,
            body = text,
            subText = subText,
            postedAt = notification.postTime,
        )
    }

    /**
     * Removals are ignored. A dismissed alert does not un-spend the money, and
     * acting on removal would let a user delete transactions by swiping.
     */
    override fun onNotificationRemoved(sbn: StatusBarNotification?) = Unit
}
