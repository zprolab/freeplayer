package com.zprolab.FreePlayer.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// The app is always light-content (like the desktop main version):
// content area #fafafa, sidebar #292b2f. Theme is fixed, no dynamic color.
private val LightColorScheme = lightColorScheme(
    primary = Fp.Orange,
    onPrimary = Color.White,
    secondary = Fp.Blue,
    tertiary = Fp.Green,
    background = Fp.ContentBg,
    onBackground = Fp.TextPrimary,
    surface = Color.White,
    onSurface = Fp.TextPrimary,
    surfaceVariant = Fp.BorderLight,
    onSurfaceVariant = Fp.TextSecondary,
    outline = Fp.Border,
    error = Fp.Red,
    onError = Color.White,
)

private val DarkColorScheme = darkColorScheme(
    primary = Fp.Orange,
    onPrimary = Color.White,
    secondary = Fp.Blue,
    tertiary = Fp.Green,
    background = Fp.Darker,
    onBackground = Fp.TextInverse,
    surface = Fp.Dark,
    onSurface = Fp.TextInverse,
    surfaceVariant = Fp.SidebarActive,
    onSurfaceVariant = Fp.TextInverse,
    outline = Fp.BorderDark,
    error = Fp.Red,
    onError = Color.White,
)

@Composable
fun FreePlayerTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme,
        typography = Typography,
        content = content
    )
}
