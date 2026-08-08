package com.zprolab.FreePlayer.media

import android.content.Intent
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
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = PlayerController.getPlayer()
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
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
