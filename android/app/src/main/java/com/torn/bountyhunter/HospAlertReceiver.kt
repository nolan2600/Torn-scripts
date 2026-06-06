package com.torn.bountyhunter

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.torn.bountyhunter.data.Prefs

class HospAlertReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val targetId = intent.getIntExtra("target_id", -1)
        if (targetId < 0) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) return

        val targetName = intent.getStringExtra("target_name") ?: "Unknown"
        val reward = intent.getLongExtra("reward", 0L)
        val hospUntil = intent.getLongExtra("hosp_until", 0L)
        val revivable = intent.getBooleanExtra("revivable", false)

        // Consume the watch for this target
        val prefs = Prefs(context)
        val watched = prefs.watchedTargetIds.toMutableSet()
        watched.remove(targetId.toString())
        prefs.watchedTargetIds = watched

        val remSec = maxOf(0L, hospUntil - System.currentTimeMillis() / 1_000L)
        val remLabel = if (remSec <= 0) "out NOW" else "~${remSec}s"

        val openIntent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(
            context, targetId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val body = buildString {
            append("Reward: ${formatMoney(reward)}")
            if (revivable) append(" · Revivable")
        }

        val notif = NotificationCompat.Builder(context, BountyHunterApp.NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("★ $targetName exits hospital $remLabel")
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(targetId + 100_000, notif)
    }

    private fun formatMoney(n: Long): String = when {
        n >= 1_000_000_000L -> "\$${"%.2f".format(n / 1_000_000_000.0)}B"
        n >= 1_000_000L     -> "\$${"%.2f".format(n / 1_000_000.0)}M"
        n >= 1_000L         -> "\$${"%.1f".format(n / 1_000.0)}K"
        else                -> "\$$n"
    }
}
