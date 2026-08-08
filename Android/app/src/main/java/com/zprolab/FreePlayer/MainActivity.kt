package com.zprolab.FreePlayer

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import com.zprolab.FreePlayer.playback.PlayerController
import com.zprolab.FreePlayer.ui.MainScreen
import com.zprolab.FreePlayer.ui.PlayerViewModel
import com.zprolab.FreePlayer.ui.theme.FreePlayerTheme

class MainActivity : ComponentActivity() {

    private val viewModel: PlayerViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Match the desktop-style chrome: app content owns the top edge.
        WindowCompat.getInsetsController(window, window.decorView)
            .hide(WindowInsetsCompat.Type.statusBars())
        PlayerController.init(applicationContext)
        val requestedPermissions = buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (requestedPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, requestedPermissions.toTypedArray(), 1)
        }
        setContent {
            FreePlayerTheme {
                MainScreen(Modifier.fillMaxSize())
            }
        }

        // Audio files shared/open from other apps ("open with" FreePlayer) →
        // import them into the library right away.
        handleSharedAudio(intent)

        // Global keyboard shortcuts are handled inside the Compose tree
        // (MainScreen root Modifier.onKeyEvent), where TextFields consume
        // their own keys first — space/v still work everywhere else.
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSharedAudio(intent)
    }

    private fun handleSharedAudio(intent: Intent?) {
        val uris = mutableListOf<Uri>()
        when (intent?.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> {
                // Real share sheets pass ArrayList<Parcelable>; some sources
                // (adb, certain apps) pass String[] instead — accept both.
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.addAll(it) }
                if (uris.isEmpty()) {
                    intent.getStringArrayListExtra(Intent.EXTRA_STREAM)?.forEach { uris.add(Uri.parse(it)) }
                }
                if (uris.isEmpty()) {
                    intent.getExtras()?.getStringArray(Intent.EXTRA_STREAM)?.forEach { uris.add(Uri.parse(it)) }
                }
            }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
        }
        if (uris.isEmpty()) return

        viewModel.importSharedUris(uris) { imported, failed ->
            runOnUiThread {
                val msg = when {
                    failed > 0 -> "Imported $imported track(s), $failed failed"
                    imported > 0 -> "Imported $imported track(s)"
                    else -> "No supported audio files"
                }
                Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
            }
        }
    }
}
