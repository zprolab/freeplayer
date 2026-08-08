package com.zprolab.FreePlayer.ui.components

import android.graphics.BitmapFactory
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.zprolab.FreePlayer.ui.theme.Fp
import com.zprolab.FreePlayer.util.CoverCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun LoadingSpinner(modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        CircularProgressIndicator(
            color = Fp.Orange,
            strokeWidth = 2.dp,
            modifier = Modifier.size(28.dp),
        )
    }
}

/**
 * Cover art with async load + LRU cache (port of CoverArt + coverCache).
 */
@Composable
fun CoverArt(
    coverPath: String?,
    size: Dp,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 8.dp,
    fallbackTint: Color = Color(0xFFe0e0e0),
) {
    var bitmap by remember(coverPath) { mutableStateOf<android.graphics.Bitmap?>(null) }
    var loading by remember(coverPath) { mutableStateOf(true) }

    LaunchedEffect(coverPath) {
        loading = true
        bitmap = withContext(Dispatchers.IO) {
            val path = coverPath ?: return@withContext null
            if (path.startsWith("data:")) return@withContext null
            val cached = CoverCache.getCachedCover(path)
            if (cached != null) return@withContext decodeCover(cached)
            val file = File(path)
            if (!file.exists()) return@withContext null
            val bytes = file.readBytes()
            CoverCache.setCachedCover(path, bytes)
            decodeCover(bytes)
        }
        loading = false
    }

    Box(
        modifier
            .size(size)
            .background(Fp.BorderLight, RoundedCornerShape(cornerRadius)),
        contentAlignment = Alignment.Center,
    ) {
        val bmp = bitmap
        if (bmp != null) {
            Image(
                painter = BitmapPainter(bmp.asImageBitmap()),
                contentDescription = null,
                modifier = Modifier.size(size),
            )
        } else {
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = fallbackTint,
                modifier = Modifier.size(size * 0.45f),
            )
        }
    }
}

private fun decodeCover(bytes: ByteArray): android.graphics.Bitmap? {
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
}

@Composable
fun MonoText(text: String, size: Int = 11, color: Color = Fp.TextSecondary, weight: FontWeight = FontWeight.Normal) {
    Text(
        text = text,
        fontSize = size.sp,
        color = color,
        fontWeight = weight,
        fontFamily = FontFamily.Monospace,
    )
}

@Composable
fun EqualizerBars(active: Boolean, color: Color = Fp.Orange, modifier: Modifier = Modifier) {
    Box(modifier.size(width = 16.dp, height = 14.dp), contentAlignment = Alignment.Center) {
        if (!active) return@Box
        // Desktop eq-bar animation: three 2px bars, 0.8s loop with stagger
        val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "eq")
        androidx.compose.foundation.layout.Row(
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            repeat(3) { i ->
                val scale by transition.animateFloat(
                    initialValue = 0.5f,
                    targetValue = 1f,
                    animationSpec = androidx.compose.animation.core.infiniteRepeatable(
                        animation = androidx.compose.animation.core.tween(
                            durationMillis = 400,
                            easing = androidx.compose.animation.core.FastOutSlowInEasing,
                            delayMillis = i * 120,
                        ),
                        repeatMode = androidx.compose.animation.core.RepeatMode.Reverse,
                    ),
                    label = "eq$i",
                )
                Box(
                    Modifier
                        .width(2.dp)
                        .height(14.dp * scale)
                        .background(color, CircleShape)
                )
            }
        }
    }
}
