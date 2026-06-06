package com.torn.bountyhunter

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

class BountyHunterApp : Application() {

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Hospital Exit Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Alerts when a watched bounty target is about to leave hospital" }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    companion object {
        const val NOTIF_CHANNEL_ID = "bh_hosp_alerts"
    }
}
