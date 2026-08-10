package com.zprolab.FreePlayer.media

import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionResult
import com.zprolab.FreePlayer.playback.PlayerController

/**
 * Foreground service hosting the MediaSession — the Android counterpart of
 * the tray menu + system media keys on desktop. Notification keeps playback
 * alive in the background; media keys route through the session callbacks.
 *
 * Play/pause commands act on the shared ExoPlayer directly (default wiring);
 * next/previous are intercepted because the player holds a single media item
 * while PlayerController owns the queue.
 */
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        PlayerController.init(applicationContext)
        val player = PlayerController.getOrCreatePlayer()
        mediaSession = MediaSession.Builder(this, player)
            .setCallback(PlaybackSessionCallback())
            .build()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // startForegroundService requires startForeground within 5s; media3
        // promotes the notification only once playback actually starts, so on
        // cold start there is a window where we'd crash. Promote early with a
        // placeholder; media3 replaces it with the media notification.
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("FreePlayer")
            .setContentText("Playback")
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return super.onStartCommand(intent, flags, startId)
    }

    private fun createNotificationChannel() {
        val channel = android.app.NotificationChannel(
            CHANNEL_ID,
            "Playback",
            android.app.NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(android.app.NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = PlayerController.getPlayer()
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    companion object {
        private const val CHANNEL_ID = "playback"
        private const val NOTIFICATION_ID = 1
    }

    override fun onDestroy() {
        mediaSession?.run {
            release()
        }
        mediaSession = null
        super.onDestroy()
    }

    private class PlaybackSessionCallback : MediaSession.Callback {
        override fun onPlayerCommandRequest(
            mediaSession: MediaSession,
            controllerInfo: MediaSession.ControllerInfo,
            playerCommand: Int,
        ): Int {
            return when (playerCommand) {
                // PlayerController owns the queue; route next/prev to it and
                // reject the default command so media3 doesn't also run
                // seekToNextMediaItem on the single-item player.
                Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM -> {
                    PlayerController.next()
                    SessionResult.RESULT_ERROR_BAD_VALUE
                }
                Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM -> {
                    PlayerController.prev()
                    SessionResult.RESULT_ERROR_BAD_VALUE
                }
                else -> SessionResult.RESULT_SUCCESS
            }
        }
    }
}
