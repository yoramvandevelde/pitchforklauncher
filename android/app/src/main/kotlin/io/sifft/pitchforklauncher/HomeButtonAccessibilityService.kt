/*
 * PitchforkLauncher
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

package io.sifft.pitchforklauncher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * KEYCODE_HOME is normally reserved by the system and can't be intercepted by a regular
 * Activity. An AccessibilityService with the FILTER_KEY_EVENTS capability is one of the few
 * ways to see it before the system's own launcher-switch handling consumes it, which lets
 * PitchforkLauncher act as the effective home screen without being registered as the default
 * launcher (and without disabling the stock one, which breaks the remote's YouTube button on
 * Google TV).
 *
 * Other remote buttons (e.g. the dedicated YouTube button, which doesn't send a standard
 * Android keycode) can be freely remapped to launch any app — see `ButtonMappings` and the
 * "Remote buttons" settings panel. Handling them here, rather than relying on whatever normally
 * reacts to them, means they keep working even if the stock launcher gets disabled (README
 * "Option B").
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

    // Keycodes whose ACTION_DOWN this service has swallowed, so the matching ACTION_UP is
    // swallowed too even if the claim check below would (rarely, e.g. mid-press mapping change)
    // disagree by then. See onKeyEvent's doc comment for why DOWN needs to be consumed at all.
    private val consumedKeyCodes = mutableSetOf<Int>()

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    /**
     * Only consuming ACTION_UP (the pre-existing behavior below `handleKeyUp`) leaves
     * ACTION_DOWN for the same key press to fall through to whatever's underneath — the
     * foreground app, or the system. That's the classic shape of a both-things-fire bug: this
     * hardware happens to ignore the stray DOWN, but other firmware may act on it (e.g. treat it
     * as its own distinct press), racing against this service's UP-triggered launch. So any
     * keycode this service is actually going to act on has both its DOWN and UP consumed —
     * [isClaimedKeyCode] below mirrors the same conditions `handleKeyUp` checks, and
     * [consumedKeyCodes] carries that DOWN-time decision forward to the matching UP.
     */
    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_UP) {
            return handleKeyUp(event)
        }
        if (isClaimedKeyCode(event.keyCode)) {
            consumedKeyCodes.add(event.keyCode)
            return true
        }
        return super.onKeyEvent(event)
    }

    private fun isClaimedKeyCode(keyCode: Int): Boolean {
        if (ButtonCapture.active && keyCode !in RESERVED_KEYCODES) return true
        if (keyCode == KeyEvent.KEYCODE_HOME) return true
        // RESERVED_KEYCODES (other than Home, handled above) can never have a ButtonMappings
        // entry — the capture dialog itself excludes them as a target — so skip straight past
        // the SharedPreferences/PackageManager lookup below for the highest-traffic keys
        // (D-pad navigation) this service sees.
        if (keyCode in RESERVED_KEYCODES) return false
        val packageName = ButtonMappings.get(this, keyCode) ?: return false
        return packageManager.resolveLaunchIntent(packageName)?.intent != null
    }

    private fun handleKeyUp(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        val downWasConsumed = consumedKeyCodes.remove(keyCode)

        if (ButtonCapture.active && keyCode !in RESERVED_KEYCODES) {
            ButtonCapture.onCaptured?.invoke(keyCode)
            ButtonCapture.onCaptured = null
            return true
        }

        if (keyCode == KeyEvent.KEYCODE_HOME) {
            startActivity(Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            })
            return true
        }

        ButtonMappings.get(this, keyCode)?.let { packageName ->
            val launchIntent = packageManager.resolveLaunchIntent(packageName)?.intent
            if (launchIntent != null) {
                startActivity(launchIntent.apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
                return true
            }
        }

        return if (downWasConsumed) true else super.onKeyEvent(event)
    }
}
