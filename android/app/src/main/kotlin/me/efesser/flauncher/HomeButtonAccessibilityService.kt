/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * KEYCODE_HOME is normally reserved by the system and can't be intercepted by a regular
 * Activity. An AccessibilityService with the FILTER_KEY_EVENTS capability is one of the few
 * ways to see it before the system's own launcher-switch handling consumes it, which lets
 * FLauncher act as the effective home screen without being registered as the default launcher
 * (and without disabling the stock one, which breaks the remote's YouTube button on Google TV).
 *
 * The remote's dedicated YouTube button doesn't send a standard keycode — on this Google TV
 * Streamer remote it's KEYCODE_BUTTON_3 (190). Handling it here too means the button keeps
 * working even if the stock launcher gets disabled (README "Method 2"), since that's normally
 * what's responsible for reacting to it.
 */
class HomeButtonAccessibilityService : AccessibilityService() {

    companion object {
        private const val KEYCODE_YOUTUBE_BUTTON = 190 // KeyEvent.KEYCODE_BUTTON_3
        private const val YOUTUBE_PACKAGE = "com.google.android.youtube.tv"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_UP) {
            return super.onKeyEvent(event)
        }
        when (event.keyCode) {
            KeyEvent.KEYCODE_HOME -> {
                startActivity(Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                })
                return true
            }
            KEYCODE_YOUTUBE_BUTTON -> {
                val launchIntent = packageManager.getLaunchIntentForPackage(YOUTUBE_PACKAGE) ?: return super.onKeyEvent(event)
                startActivity(launchIntent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                return true
            }
        }
        return super.onKeyEvent(event)
    }
}
