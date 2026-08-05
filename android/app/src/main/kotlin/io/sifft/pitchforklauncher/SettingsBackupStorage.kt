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

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import java.io.File

/**
 * Reads/writes the settings-backup JSON to the real, shared Downloads folder using a plain
 * [File], gated on the "All files access" (`MANAGE_EXTERNAL_STORAGE`) permission.
 *
 * This isn't the first thing tried: an earlier version went through `MediaStore.Downloads`
 * instead, which needs no permission at all for rows an app inserted itself -- but confirmed
 * on-device (and independently documented as a general Android limitation, not an OEM quirk),
 * `MediaProvider` does not preserve that ownership across an uninstall/reinstall. Since surviving
 * exactly that (recovering settings after a reset or on a new device) is the whole point of this
 * feature, `MediaStore` couldn't actually deliver it. `MANAGE_EXTERNAL_STORAGE` sidesteps the
 * ownership question entirely: once granted, plain file paths under the real Downloads folder
 * work regardless of which app (or install of this app) wrote them. This is the same trade-off
 * file-manager-style apps make, and reasonable here since PitchforkLauncher isn't on the Play
 * Store, where this permission needs a declared justification most apps don't have.
 *
 * The permission is a one-time manual grant via a system Settings screen (not a runtime dialog),
 * and -- like any permission -- is reset on uninstall, so it needs granting again after a fresh
 * install. That's an acceptable one-time step in the same vein as this app's existing "Set as Home
 * button target" setup, and still needs no file-picker UI: "Backup"/"Restore" stay two fixed
 * buttons, no "which file" choice.
 */
object SettingsBackupStorage {
    private val downloadsDirectory: File
        get() = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

    /** Whether the underlying API (`Environment.isExternalStorageManager()`,
     * `ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION`) exists on this OS version at all -- both
     * were introduced in API 30 (R). Distinct from [isAvailable]: this app's minSdk is 24, so a
     * device below R can reach this code with no way to ever grant the permission, which
     * [requestAccessIntent] needs to know before trying to resolve an intent action that doesn't
     * exist yet. */
    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    fun isAvailable(): Boolean = isSupported() && Environment.isExternalStorageManager()

    fun write(fileName: String, bytes: ByteArray): Boolean {
        if (!isAvailable()) return false
        return try {
            downloadsDirectory.mkdirs()
            // Write to a temp file and rename over the target rather than truncating it directly:
            // a rename within the same directory is atomic, so a crash, full disk, or failed write
            // partway through leaves the previous good backup in place instead of a half-written
            // replacement that Restore would then choke on.
            val target = File(downloadsDirectory, fileName)
            val tempFile = File(downloadsDirectory, "$fileName.tmp")
            tempFile.writeBytes(bytes)
            tempFile.renameTo(target)
        } catch (e: Exception) {
            false
        }
    }

    fun read(fileName: String): ByteArray? {
        if (!isAvailable()) return null
        val file = File(downloadsDirectory, fileName)
        if (!file.exists()) return null
        return try {
            file.readBytes()
        } catch (e: Exception) {
            null
        }
    }

    /** Opens the system Settings screen where the user grants/revokes "All files access". */
    fun requestAccessIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:${context.packageName}"),
        )
}