package com.mafiadealer.game

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        channels()
    }

    /** The push channels the server sends to (push.ts CHANNEL). Created again on every start so the names follow the language. */
    private fun channels() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(NotificationManager::class.java)
        for ((id, name, desc, importance) in listOf(
            Quad("invites", R.string.ch_invites, R.string.ch_invites_d, NotificationManager.IMPORTANCE_HIGH),
            Quad("friends", R.string.ch_friends, R.string.ch_friends_d, NotificationManager.IMPORTANCE_DEFAULT),
            Quad("approvals", R.string.ch_approvals, R.string.ch_approvals_d, NotificationManager.IMPORTANCE_DEFAULT),
            Quad("titles", R.string.ch_titles, R.string.ch_titles_d, NotificationManager.IMPORTANCE_DEFAULT),
            Quad("updates", R.string.ch_updates, R.string.ch_updates_d, NotificationManager.IMPORTANCE_DEFAULT),
        )) nm.createNotificationChannel(NotificationChannel(id, getString(name), importance).apply { description = getString(desc) })
    }
    private data class Quad(val id: String, val name: Int, val desc: Int, val importance: Int)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "mafia/keep": start / stop the service that keeps a hosted Wi-Fi room alive (KeepService), and open this app's
        // notification settings (Settings → Notifications)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mafia/keep")
        Updates.onStatus = { status, message -> runOnUiThread { ch.invokeMethod("installStatus", mapOf("status" to status, "message" to message)) } }
        ch.setMethodCallHandler { call, result ->
            val intent = Intent(this, KeepService::class.java)
            when (call.method) {
                "start" -> {
                    intent.putExtra("title", call.argument<String>("title")).putExtra("text", call.argument<String>("text"))
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "stop" -> { stopService(intent); result.success(true) }
                "notifSettings" -> {
                    val i = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", packageName, null))
                    startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                // in-app updates (S8-4)
                "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                "allowInstalls" -> {
                    if (Build.VERSION.SDK_INT >= 26) startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")))
                    result.success(true)
                }
                // [R7] a buzz or a ping: the old app's double vibration (navigator.vibrate([90, 60, 90]))
                "vibrate" -> {
                    val v = if (Build.VERSION.SDK_INT >= 31) getSystemService(VibratorManager::class.java).defaultVibrator
                        else @Suppress("DEPRECATION") (getSystemService(VIBRATOR_SERVICE) as Vibrator)
                    val pattern = longArrayOf(0, 90, 60, 90)
                    if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pattern, -1)) else @Suppress("DEPRECATION") v.vibrate(pattern, -1)
                    result.success(true)
                }
                "cacheDir" -> result.success(cacheDir.absolutePath)
                // [S19, Quin Q4] the suggestions box says which Android sent it (Platform gives the kernel's version)
                "android" -> result.success("Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
                "install" -> try { Updates.install(this, call.argument<String>("path")!!); result.success(true) } catch (e: Exception) { result.error("install", e.message, null) }
                "openUrl" -> { startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.argument<String>("url"))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }
}
