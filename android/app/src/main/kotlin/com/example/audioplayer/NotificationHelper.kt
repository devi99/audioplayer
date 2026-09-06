package com.example.audioplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NotificationHelper(private val context: Context) {
    companion object {
        private const val CHANNEL_ID = "audioplayer_notification_channel"
        private const val CHANNEL_NAME = "Audio Player"
        private const val NOTIFICATION_ID = 1
        private const val MEDIA_CHANNEL = "com.example.audioplayer/media"
        
        private var notificationManager: NotificationManager? = null
        private var mediaChannel: MethodChannel? = null
        
        fun initFlutterChannel(flutterEngine: FlutterEngine) {
            mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)
        }
        
        fun sendMediaAction(context: Context, action: String) {
            mediaChannel?.invokeMethod(action, null)
            // Also try the main notification channel as fallback
            try {
                val channel = MethodChannel(MethodChannel(context, "com.example.audioplayer/notification").binaryMessenger, "com.example.audioplayer/notification")
                channel.invokeMethod("onMediaAction", action)
            } catch (e: Exception) {
                // Ignore fallback failure
            }
        }
        
        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                )
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.createNotificationChannel(channel)
            }
        }
        
        fun showNotification(context: Context, title: String, artist: String, isPlaying: Boolean) {
            // Start the AudioService which will show a foreground notification with controls
            AudioService.startService(context, title, artist, isPlaying)
        }
        
        fun hideNotification(context: Context) {
            AudioService.stopService(context)
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
        }
        
        fun updateNotification(context: Context, title: String, artist: String, isPlaying: Boolean) {
            AudioService.updateNotification(context, title, artist, isPlaying)
        }
    }
}
