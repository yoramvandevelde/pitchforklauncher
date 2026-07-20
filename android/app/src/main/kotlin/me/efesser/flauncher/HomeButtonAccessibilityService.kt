/*
 * FLauncher
 * Copyright (C) 2026  Yoram van de Velde
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
 * Other remote buttons (e.g. the dedicated YouTube button, which doesn't send a standard
 * Android keycode) can be freely remapped to launch any app — see `ButtonMappings` and the
 * "Remote buttons" settings panel. Handling them here, rather than relying on whatever normally
 * reacts to them, means they keep working even if the stock launcher gets disabled (README
 * "Method 2").
 */
class HomeButtonAccessibilityService : AccessibilityService() {

    companion object {
        // Keys that are never remappable: Home is FLauncher's own core feature, navigation keys
        // are needed to operate FLauncher's own UI (including the "press a button" capture
        // dialog itself — without this exclusion, the D-pad/select presses used to reach its
        // Cancel button get captured as the mapping target instead of reaching the UI), and the
        // rest are risky to hijack (could leave the device impossible to control, or in the case
        // of the assistant key, fights with Android's own Assistant overlay).
        private val RESERVED_KEYCODES = setOf(
            KeyEvent.KEYCODE_HOME,
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_POWER,
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN,
            KeyEvent.KEYCODE_VOLUME_MUTE,
            KeyEvent.KEYCODE_ASSIST,
            KeyEvent.KEYCODE_VOICE_ASSIST,
        )
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_UP) {
            return super.onKeyEvent(event)
        }

        if (ButtonCapture.active && event.keyCode !in RESERVED_KEYCODES) {
            ButtonCapture.onCaptured?.invoke(event.keyCode)
            ButtonCapture.onCaptured = null
            return true
        }

        if (event.keyCode == KeyEvent.KEYCODE_HOME) {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            })
            return true
        }

        ButtonMappings.get(this, event.keyCode)?.let { packageName ->
            // Android TV apps commonly only declare LEANBACK_LAUNCHER, not the regular LAUNCHER
            // category getLaunchIntentForPackage() alone looks for -- matches MainActivity's own
            // launchApp(), which needs the same fallback for the same reason.
            val launchIntent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
                ?: packageManager.getLaunchIntentForPackage(packageName)
                ?: return super.onKeyEvent(event)
            startActivity(launchIntent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
            return true
        }

        return super.onKeyEvent(event)
    }
}
