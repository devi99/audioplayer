package com.example.audioplayer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AudioService : Service() {
    companion object {
        private const val CHANNEL_ID = "audioplayer_media_channel"
        private const val CHANNEL_NAME = "Audio Player Media"
        private const val NOTIFICATION_ID = 1001
        private const val ACTION_PLAY = "ACTION_PLAY"
        private const val ACTION_PAUSE = "ACTION_PAUSE"
        private const val ACTION_NEXT = "ACTION_NEXT"
        private const val ACTION_PREVIOUS = "ACTION_PREVIOUS"
        private const val ACTION_STOP = "ACTION_STOP"
        
        fun startService(context: Context, title: String, artist: String, isPlaying: Boolean) {
            val intent = Intent(context, AudioService::class.java).apply {
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("isPlaying", isPlaying)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stopService(context: Context) {
            val intent = Intent(context, AudioService::class.java)
            context.stopService(intent)
        }
        
        fun updateNotification(context: Context, title: String, artist: String, isPlaying: Boolean) {
            val intent = Intent(context, AudioService::class.java).apply {
                action = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("isPlaying", isPlaying)
            }
            context.startService(intent)
        }
    }
    
    private lateinit var notificationManager: NotificationManager
    
    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Audio Player Notification Channel"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent ?: return START_NOT_STICKY
        
        val title = intent.getStringExtra("title") ?: ""
        val artist = intent.getStringExtra("artist") ?: ""
        val isPlaying = intent.getBooleanExtra("isPlaying", false)
        
        when (intent.action) {
            ACTION_PLAY -> {
                // Handle play action
                showNotification(title, artist, true)
            }
            ACTION_PAUSE -> {
                // Handle pause action
                showNotification(title, artist, false)
            }
            ACTION_NEXT -> {
                // Send next action to Flutter via method channel
                NotificationHelper.sendMediaAction(this, "next")
            }
            ACTION_PREVIOUS -> {
                // Send previous action to Flutter via method channel
                NotificationHelper.sendMediaAction(this, "previous")
            }
            ACTION_STOP -> {
                // Stop the service
                stopForeground(true)
                stopSelf()
            }
            else -> {
                // Normal start - show notification
                showNotification(title, artist, isPlaying)
            }
        }
        
        return START_STICKY
    }
    
    private fun showNotification(title: String, artist: String, isPlaying: Boolean) {
        val playPauseIcon = if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        val playPauseText = if (isPlaying) "Pause" else "Play"
        
        // Intent for opening the app
        val contentIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for play/pause
        val playPauseIntent = Intent(this, AudioService::class.java).apply {
            action = if (isPlaying) ACTION_PAUSE else ACTION_PLAY
            putExtra("title", title)
            putExtra("artist", artist)
        }
        val playPausePendingIntent = PendingIntent.getService(
            this,
            1,
            playPauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for next
        val nextIntent = Intent(this, AudioService::class.java).apply {
            action = ACTION_NEXT
            putExtra("title", title)
            putExtra("artist", artist)
        }
        val nextPendingIntent = PendingIntent.getService(
            this,
            2,
            nextIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for previous
        val previousIntent = Intent(this, AudioService::class.java).apply {
            action = ACTION_PREVIOUS
            putExtra("title", title)
            putExtra("artist", artist)
        }
        val previousPendingIntent = PendingIntent.getService(
            this,
            3,
            previousIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Intent for stop
        val stopIntent = Intent(this, AudioService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            4,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setLargeIcon(BitmapFactory.decodeResource(resources, android.R.drawable.ic_media_play))
            .setContentIntent(contentPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_media_previous, "Previous", previousPendingIntent)
            .addAction(playPauseIcon, playPauseText, playPausePendingIntent)
            .addAction(android.R.drawable.ic_media_next, "Next", nextPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .build()
        
        startForeground(NOTIFICATION_ID, notification)
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        super.onDestroy()
    }
}