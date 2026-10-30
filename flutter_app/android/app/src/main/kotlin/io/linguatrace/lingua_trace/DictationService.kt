package io.linguatrace.lingua_trace

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Runs while dictating: Android lets the recogniser hear us with the screen
 * off only while the app has a foreground service of the microphone type.
 * Shows «LinguaTrace слушает» in the notification shade.
 */
class DictationService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val n = notification()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else {
                startForeground(ID, n)
            }
            if (wakeLock == null) {
                wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "LinguaTrace:dictation")
                    .apply { acquire(3 * 60 * 60 * 1000L) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "dictation service: $e")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun notification(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL, "Диктовка", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return builder()
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("LinguaTrace слушает")
            .setContentText("Идёт диктовка. Нажмите, чтобы открыть.")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }

    @Suppress("DEPRECATION")
    private fun builder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else Notification.Builder(this)

    companion object {
        private const val ID = 7301
        private const val CHANNEL = "dictation"
        private const val TAG = "LinguaTrace"

        fun start(c: Context) {
            try {
                val i = Intent(c, DictationService::class.java)
                if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i) else c.startService(i)
            } catch (e: Exception) {
                Log.w(TAG, "dictation service: $e")
            }
        }

        fun stop(c: Context) {
            try {
                c.stopService(Intent(c, DictationService::class.java))
            } catch (_: Exception) {
            }
        }
    }
}
