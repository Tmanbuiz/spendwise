package com.spendwise.spendwise

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val METHOD_CHANNEL = "com.spendwise/notifications"
        const val EVENT_CHANNEL = "com.spendwise/notifications/stream"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Either the activity or the service may be the first component
        // Android creates, so both attach storage.
        NotificationBridge.attach(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(isNotificationAccessGranted())
                    "openNotificationSettings" -> {
                        openNotificationAccessSettings()
                        result.success(null)
                    }
                    "setWatchedPackages" -> {
                        val packages = call.arguments as? List<*>
                        NotificationBridge.setWatchedPackages(
                            packages?.filterIsInstance<String>()?.toSet() ?: emptySet()
                        )
                        result.success(null)
                    }
                    "isListenerConnected" -> result.success(NotificationBridge.isListenerConnected())
                    "rescanActive" -> result.success(NotificationBridge.rescanActive())
                    "drainPending" -> result.success(NotificationBridge.drainQueue())
                    "captureStats" -> result.success(NotificationBridge.stats())
                    "resetCaptureStats" -> {
                        NotificationBridge.resetStats()
                        result.success(null)
                    }
                    "findInstalledApps" -> {
                        val wanted = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>()
                            ?: emptyList()
                        result.success(findInstalledApps(wanted))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationBridge.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    NotificationBridge.setEventSink(null)
                }
            })
    }

    /**
     * Reports which of [wanted] package names are actually installed.
     *
     * This asks the package manager a yes/no question about specific, declared
     * package names — it does not enumerate the user's apps, and it reads no
     * notification content. It exists so bank detection is verified rather
     * than assumed: if CIBC ships under a package id we did not predict, the
     * user sees "not detected" instead of alerts silently going nowhere.
     *
     * Android 11+ hides packages not declared in the manifest's <queries>
     * element, so each id here must also be listed there.
     */
    private fun findInstalledApps(wanted: List<String>): List<Map<String, String>> {
        val pm = packageManager
        return wanted.mapNotNull { packageName ->
            try {
                val info = pm.getApplicationInfo(packageName, 0)
                mapOf(
                    "packageName" to packageName,
                    "label" to pm.getApplicationLabel(info).toString(),
                )
            } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                null
            }
        }
    }

    /**
     * Reads the grant straight from Settings.Secure rather than trusting any
     * cached flag, because the user can revoke notification access at any time
     * from system settings without the app being told.
     */
    private fun isNotificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false

        val expected = ComponentName(
            this,
            SpendWiseNotificationListenerService::class.java,
        )
        return enabled.split(":").any { entry ->
            ComponentName.unflattenFromString(entry) == expected
        }
    }

    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
