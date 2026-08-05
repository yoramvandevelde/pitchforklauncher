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

import android.content.Intent
import android.content.pm.PackageManager

data class ResolvedLaunchIntent(val intent: Intent, val sideloaded: Boolean)

/**
 * Android TV apps commonly only declare LEANBACK_LAUNCHER, not the regular LAUNCHER category;
 * getLaunchIntentForPackage() alone looks for LAUNCHER, so both are needed to cover TV and
 * sideloaded (phone/tablet-style) apps.
 */
fun PackageManager.resolveLaunchIntent(packageName: String): ResolvedLaunchIntent? {
    getLeanbackLaunchIntentForPackage(packageName)?.let { return ResolvedLaunchIntent(it, sideloaded = false) }
    return getLaunchIntentForPackage(packageName)?.let { ResolvedLaunchIntent(it, sideloaded = true) }
}
