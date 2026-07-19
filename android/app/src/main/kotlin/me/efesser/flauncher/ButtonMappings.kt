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

import android.content.Context

/**
 * Persists which app each remote button (other than Home, which is fixed) launches. Backed by a
 * dedicated SharedPreferences file rather than Flutter's own shared_preferences plugin storage,
 * so HomeButtonAccessibilityService — which doesn't have a Flutter engine attached — can read it
 * directly.
 */
object ButtonMappings {
    private const val PREFS_NAME = "button_mappings"
    private const val SEEDED_KEY = "_seeded"

    // KEYCODE_BUTTON_3 (190) on this Google TV Streamer remote; see DRIFT.md.
    private const val DEFAULT_YOUTUBE_KEYCODE = "190"
    private const val DEFAULT_YOUTUBE_PACKAGE = "com.google.android.youtube.tv"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun seedDefaultsIfEmpty(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(SEEDED_KEY, false)) {
            p.edit()
                .putString(DEFAULT_YOUTUBE_KEYCODE, DEFAULT_YOUTUBE_PACKAGE)
                .putBoolean(SEEDED_KEY, true)
                .apply()
        }
    }

    fun all(context: Context): Map<Int, String> =
        prefs(context).all
            .mapNotNull { (key, value) -> key.toIntOrNull()?.let { it to value as String } }
            .toMap()

    fun get(context: Context, keyCode: Int): String? = prefs(context).getString(keyCode.toString(), null)

    fun set(context: Context, keyCode: Int, packageName: String) {
        prefs(context).edit().putString(keyCode.toString(), packageName).apply()
    }

    fun remove(context: Context, keyCode: Int) {
        prefs(context).edit().remove(keyCode.toString()).apply()
    }
}
