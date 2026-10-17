package com.tabmonitor.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Manages native persistent Android notifications for TabMonitor.
 * Displays connection status, battery percentage, charging state,
 * and a live ticking countdown timer (chronometer) to the next upload.
 */
object TabMonitorNotificationManager {
    const val NOTIFICATION_CHANNEL_ID = "tabmonitor_status"
    const val NOTIFICATION_ID = 1001

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "TabMonitor Stav"
            val descriptionText = "Zobrazuje stav pripojenia tabletu a odpočet do ďalšieho odoslania hlásenia."
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
            }
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun updateStatusNotification(
        context: Context,
        deviceId: String,
        batteryLevel: Int,
        isCharging: Boolean,
        isOnline: Boolean,
        statusMessage: String,
        nextReportSeconds: Int
    ) {
        createNotificationChannel(context)

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val chargingSymbol = if (isCharging) " ⚡" else ""
        val statusSymbol = if (isOnline) "🟢" else "🔴"
        val statusLabel = if (isOnline) "Pripojené" else "Offline"
        val title = "TabMonitor • $deviceId"
        val content = "$statusSymbol $statusLabel • Batéria: $batteryLevel%$chargingSymbol"

        // Target timestamp for Android's native ticking countdown chronometer
        val nextUploadMillis = System.currentTimeMillis() + (nextReportSeconds.coerceAtLeast(1) * 1000L)

        val builder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(content)
            .setSubText("Ďalšie odoslanie")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(nextUploadMillis)
            .setUsesChronometer(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setChronometerCountDown(true)
        }

        if (statusMessage.isNotEmpty()) {
            builder.setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$content\n$statusMessage")
            )
        }

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, builder.build())
    }

    fun cancelStatusNotification(context: Context) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
    }
}
