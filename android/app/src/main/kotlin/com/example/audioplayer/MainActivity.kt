package com.example.audioplayer

import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.audioplayer/notification"
    private val MEDIA_CHANNEL = "com.example.audioplayer/media"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize notification helper with Flutter engine
        NotificationHelper.initFlutterChannel(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    NotificationHelper.showNotification(this, title, artist, isPlaying)
                    result.success(null)
                }
                "hideNotification" -> {
                    NotificationHelper.hideNotification(this)
                    result.success(null)
                }
                "updateNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                    NotificationHelper.updateNotification(this, title, artist, isPlaying)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Set up media action channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "next" -> {
                    // Handle next action - send back to Flutter
                    result.success("next")
                }
                "previous" -> {
                    // Handle previous action - send back to Flutter
                    result.success("previous")
                }
                "play" -> {
                    result.success("play")
                }
                "pause" -> {
                    result.success("pause")
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        // Handle media actions from notification
        intent?.action?.let { action ->
            when (action) {
                "ACTION_NEXT" -> {
                    // Send next action to Flutter
                    MethodChannel(dartExecutor.binaryMessenger, MEDIA_CHANNEL).invokeMethod("next", null)
                }
                "ACTION_PREVIOUS" -> {
                    MethodChannel(dartExecutor.binaryMessenger, MEDIA_CHANNEL).invokeMethod("previous", null)
                }
                "ACTION_PLAY" -> {
                    MethodChannel(dartExecutor.binaryMessenger, MEDIA_CHANNEL).invokeMethod("play", null)
                }
                "ACTION_PAUSE" -> {
                    MethodChannel(dartExecutor.binaryMessenger, MEDIA_CHANNEL).invokeMethod("pause", null)
                }
            }
        }
    }
}
