package com.mafiadealer.game

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps a hosted Wi-Fi room alive while the screen is off or the app is in the background: a foreground service
 * (type connectedDevice, with its notification), a partial wake lock and a Wi-Fi lock. Stops when hosting ends or
 * the app is swiped away. The old app's "Keep" service, which was proven on real phones.
 */
class KeepService : Service() {
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Mafia Dealer"
        val text = intent?.getStringExtra("text") ?: ""
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // [S13-5 / his note 14] Android requires this notification while the room is kept alive in the background; it is
        // the quietest kind: no sound, folded away, no status-bar icon (a new channel: an old one's importance can't drop)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.deleteNotificationChannel("hosting")
            nm.createNotificationChannel(NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false) })
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val n = builder.setContentTitle(title).setContentText(text).setSmallIcon(R.mipmap.ic_launcher).setContentIntent(open).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE) else startForeground(ID, n)
        if (wake == null) {
            wake = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mafiadealer:host").apply { acquire() }
        }
        if (wifi == null) {
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifi = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager).createWifiLock(mode, "mafiadealer:host").apply { acquire() }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf() }

    override fun onDestroy() {
        wake?.let { if (it.isHeld) it.release() }
        wifi?.let { if (it.isHeld) it.release() }
        wake = null; wifi = null
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "hosting_quiet"
        const val ID = 8765
    }
}
