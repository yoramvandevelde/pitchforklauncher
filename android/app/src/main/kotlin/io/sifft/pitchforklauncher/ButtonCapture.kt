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

package io.sifft.pitchforklauncher

/**
 * In-process handoff between MainActivity's capture EventChannel and
 * HomeButtonAccessibilityService, which sees key events MainActivity never gets. Both run in the
 * same process (accessibility services aren't isolated by default), so a plain singleton is
 * enough — no need for a broadcast/IPC mechanism.
 */
object ButtonCapture {
    var onCaptured: ((Int) -> Unit)? = null

    val active: Boolean
        get() = onCaptured != null
}
