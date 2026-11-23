package com.mafiadealer.game

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File

/**
 * In-app updates (S8-4): the downloaded APK goes to Android's PackageInstaller. The first time Android asks the player to
 * confirm; once this app is its own installer, Android 12+ installs later updates without asking
 * (USER_ACTION_NOT_REQUIRED). Not in the Play build (Play doesn't allow self-updates).
 */
object Updates {
    /** MainActivity forwards install results to Dart ("installStatus"). */
    var onStatus: ((String, String?) -> Unit)? = null

    fun install(ctx: Context, path: String) {
        val pi = ctx.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        if (Build.VERSION.SDK_INT >= 31) params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        val id = pi.createSession(params)
        pi.openSession(id).use { s ->
            File(path).inputStream().use { input -> s.openWrite("update.apk", 0, -1).use { out -> input.copyTo(out); s.fsync(out) } }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(ctx, id, Intent(ctx, InstallReceiver::class.java), flags)
            s.commit(pending.intentSender)
        }
    }
}

/** PackageInstaller's answer: confirmation needed (shows Android's prompt), or a failure (Dart falls back to the page). */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java) else intent.getParcelableExtra(Intent.EXTRA_INTENT)) as Intent?
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)?.let { ctx.startActivity(it) }
                Updates.onStatus?.invoke("pending", null)
            }
            PackageInstaller.STATUS_SUCCESS -> {}  // the app is being replaced; UpdatedReceiver takes over
            else -> Updates.onStatus?.invoke("failed:$status", intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
        }
    }
}

/** After an update the app isn't running: a notification brings the player back ("Mafia Dealer updated · tap to open"). */
class UpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, "updates") else Notification.Builder(ctx)
        nm.notify(3, b.setSmallIcon(R.mipmap.ic_launcher).setContentTitle(ctx.getString(R.string.upd_done)).setContentText(ctx.getString(R.string.upd_open))
            .setContentIntent(open).setAutoCancel(true).build())
    }
}
