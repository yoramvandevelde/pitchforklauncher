/*
 * PitchforkLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.Intent.*
import android.content.pm.*
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.provider.Settings
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Serializable
import java.util.concurrent.Executors
import kotlin.math.roundToInt

private const val METHOD_CHANNEL = "io.sifft.pitchforklauncher/method"
private const val EVENT_CHANNEL = "io.sifft.pitchforklauncher/event"
private const val BUTTON_CAPTURE_EVENT_CHANNEL = "io.sifft.pitchforklauncher/buttonCapture"

// Icons are never displayed larger than 48dp (applications_panel_page.dart); 192 is still
// 2-4x oversampled at every display site, comfortable headroom for high-density screens without
// carrying full adaptive-icon resolution (432x432+) through encode, storage and decode for no
// visual benefit. Banners aren't capped here -- they're legitimately displayed much larger, and
// Flutter already downscales them at decode time to the actual card size (see AppCard).
private const val ICON_MAX_PNG_SIZE = 192

class MainActivity : FlutterActivity() {
    private val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()

    // MethodChannel/EventChannel handlers run on the platform (UI) thread by default -- reading/
    // writing the settings backup file synchronously there (it includes the base64-encoded
    // wallpaper, which can be several hundred KB) risks janking rendering or an ANR on slow
    // storage, and so does encoding every installed app's icon/banner to PNG on every sync
    // (cold start, and every PACKAGE_ADDED/PACKAGE_CHANGED/PACKAGES_AVAILABLE). All of those hop
    // onto this single background thread for the actual work and post the result back via
    // mainHandler, same shape `AsyncTask` used to hide before it was deprecated.
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ButtonMappings.seedDefaultsIfEmpty(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplications" -> {
                    @Suppress("UNCHECKED_CAST") val visiblePackageNames = (call.arguments as List<String>).toSet()
                    backgroundExecutor.execute {
                        val apps = getApplications(visiblePackageNames)
                        mainHandler.post { result.success(apps) }
                    }
                }
                "getAppBanner" -> {
                    val packageName = call.arguments as String
                    backgroundExecutor.execute {
                        val banner = getAppBanner(packageName)
                        mainHandler.post { result.success(banner) }
                    }
                }
                "applicationExists" -> result.success(applicationExists(call.arguments as String))
                "launchApp" -> result.success(launchApp(call.arguments as String))
                "openSettings" -> result.success(openSettings())
                "openAccessibilitySettings" -> result.success(openAccessibilitySettings())
                "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                "isDefaultLauncher" -> result.success(isDefaultLauncher())
                "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                "startAmbientMode" -> result.success(startAmbientMode())
                "getButtonMappings" -> result.success(getButtonMappings())
                "setButtonMapping" -> {
                    @Suppress("UNCHECKED_CAST") val args = call.arguments as Map<String, Any>
                    ButtonMappings.set(this, args["keyCode"] as Int, args["packageName"] as String)
                    result.success(null)
                }
                "removeButtonMapping" -> {
                    ButtonMappings.remove(this, call.arguments as Int)
                    result.success(null)
                }
                "writeSettingsBackup" -> {
                    @Suppress("UNCHECKED_CAST") val args = call.arguments as Map<String, Any>
                    val fileName = args["fileName"] as String
                    val bytes = args["bytes"] as ByteArray
                    backgroundExecutor.execute {
                        val success = SettingsBackupStorage.write(fileName, bytes)
                        mainHandler.post { result.success(success) }
                    }
                }
                "readSettingsBackup" -> {
                    val fileName = call.arguments as String
                    backgroundExecutor.execute {
                        val bytes = SettingsBackupStorage.read(fileName)
                        mainHandler.post { result.success(bytes) }
                    }
                }
                "isSettingsBackupStorageAvailable" -> result.success(SettingsBackupStorage.isAvailable())
                "isSettingsBackupStorageSupported" -> result.success(SettingsBackupStorage.isSupported())
                "openSettingsBackupStoragePermission" -> {
                    // The action this builds (and Environment.isExternalStorageManager() behind
                    // isAvailable()) doesn't exist below API 30 -- this app's minSdk is 24, so
                    // guard against resolving an intent action the OS doesn't have yet, with an
                    // ActivityNotFoundException fallback in case some OEM build still surprises us.
                    val opened = if (SettingsBackupStorage.isSupported()) {
                        try {
                            startActivity(SettingsBackupStorage.requestAccessIntent(this))
                            true
                        } catch (e: ActivityNotFoundException) {
                            false
                        }
                    } else {
                        false
                    }
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BUTTON_CAPTURE_EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink) {
                ButtonCapture.onCaptured = { keyCode -> events.success(buildKeyCodeMap(keyCode)) }
            }

            override fun onCancel(arguments: Any?) {
                ButtonCapture.onCaptured = null
            }
        })

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        events.success(mapOf("action" to "PACKAGE_REMOVED", "packageName" to packageName))
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        backgroundExecutor.execute {
                            getApplication(packageName)?.let { app ->
                                mainHandler.post { events.success(mapOf("action" to "PACKAGE_ADDED", "activityInfo" to app)) }
                            }
                        }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        backgroundExecutor.execute {
                            getApplication(packageName)?.let { app ->
                                mainHandler.post { events.success(mapOf("action" to "PACKAGE_CHANGED", "activityInfo" to app)) }
                            }
                        }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {
                        backgroundExecutor.execute {
                            val applications = packageNames.mapNotNull(::getApplication)
                            if (applications.isNotEmpty()) {
                                mainHandler.post { events.success(mapOf("action" to "PACKAGES_AVAILABLE", "activitiesInfo" to applications)) }
                            }
                        }
                    }

                    override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                }

                launcherAppsCallbacks.add(launcherAppsCallback)
                launcherApps.registerCallback(launcherAppsCallback)
            }

            override fun onCancel(arguments: Any?) {
                launcherApps.unregisterCallback(launcherAppsCallback)
                launcherAppsCallbacks.remove(launcherAppsCallback)
            }
        })
    }

    override fun onDestroy() {
        val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
        launcherAppsCallbacks.forEach(launcherApps::unregisterCallback)
        backgroundExecutor.shutdown()
        super.onDestroy()
    }

    // Only [visiblePackageNames] get a banner computed -- that's the set Dart already knows sit in
    // a visible category, i.e. the only apps that will ever actually render one (see
    // buildAppMap's includeBanner param). icon is still computed for everyone regardless, since
    // that's needed even for hidden apps (the Applications panel's Hidden tab shows it).
    private fun getApplications(visiblePackageNames: Set<String>): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.map { buildAppMap(it, false, visiblePackageNames.contains(it.packageName)) } +
                nonTvActivitiesInfo.map { buildAppMap(it, true, visiblePackageNames.contains(it.packageName)) }
    }

    // Always includes the banner -- unlike the bulk getApplications() above, this only fires on
    // PACKAGE_ADDED/PACKAGE_CHANGED/PACKAGES_AVAILABLE (an app being installed/updated), not on
    // every cold start, so it's not worth threading visibility state into this native-initiated
    // path just to skip banner computation for a rare event.
    private fun getApplication(packageName: String): Map<String, Serializable?>? =
        packageManager.resolveLaunchIntent(packageName)?.let { (intent, sideloaded) ->
            intent.resolveActivityInfo(packageManager, 0)?.let { buildAppMap(it, sideloaded, includeBanner = true) }
        }

    // Lean, banner-only counterpart to getApplication() -- used when an app newly enters a
    // visible category and needs its banner fetched on demand (see AppsService.addToCategory on
    // the Dart side). Doesn't also recompute icon like getApplication()/buildAppMap() would;
    // that's already in the database from the last sync and doesn't need refetching here.
    private fun getAppBanner(packageName: String): ByteArray? =
        packageManager.resolveLaunchIntent(packageName)?.let { (intent, _) ->
            intent.resolveActivityInfo(packageManager, 0)?.loadBanner(packageManager)?.let(::drawableToByteArray)
        }

    private fun applicationExists(packageName: String) = try {
        packageManager.getApplicationInfo(packageName, PackageManager.MATCH_UNINSTALLED_PACKAGES)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(ACTION_MAIN, null)
                    .addCategory(if (sideloaded) CATEGORY_LAUNCHER else CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean, includeBanner: Boolean) = mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to if (includeBanner) activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray) else null,
            "icon" to activityInfo.loadIcon(packageManager)?.let { drawableToByteArray(it, maxSize = ICON_MAX_PNG_SIZE) },
            "version" to packageManager.getPackageInfo(activityInfo.packageName, 0).versionName,
            "sideloaded" to sideloaded,
    )

    private fun launchApp(packageName: String) = try {
        startActivity(packageManager.resolveLaunchIntent(packageName)?.intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun openSettings() = try {
        startActivity(Intent(Settings.ACTION_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }

    private fun openAccessibilitySettings() = try {
        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }

    private fun openAppInfo(packageName: String) = try {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun uninstallApp(packageName: String) = try {
        Intent(ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun checkForGetContentAvailability() = try {
        val intentActivities = packageManager.queryIntentActivities(Intent(ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"), 0)
        intentActivities.isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun isDefaultLauncher() = try {
        val defaultLauncher = packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
        defaultLauncher?.activityInfo?.packageName == packageName
    } catch (e: Exception) {
        false
    }

    private fun getButtonMappings(): List<Map<String, Any>> =
        ButtonMappings.all(this).map { (keyCode, packageName) ->
            buildKeyCodeMap(keyCode) + ("packageName" to packageName)
        }

    private fun buildKeyCodeMap(keyCode: Int): Map<String, Any> =
        mapOf("keyCode" to keyCode, "label" to (KeyEvent.keyCodeToString(keyCode) ?: "KEYCODE_$keyCode"))

    private fun startAmbientMode() = try {
        Intent(ACTION_MAIN)
            .setClassName("com.android.systemui", "com.android.systemui.Somnambulator")
            .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    // maxSize bounds the longer side (aspect ratio preserved, never upscaled) before compressing --
    // see ICON_MAX_PNG_SIZE. Left null for banners, which are legitimately displayed larger and at
    // a size that varies with the category's own layout settings, not a single fixed bound.
    private fun drawableToByteArray(drawable: Drawable, maxSize: Int? = null): ByteArray? {
        if (drawable.intrinsicWidth <= 0 || drawable.intrinsicHeight <= 0) {
            return null
        }

        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        var bitmap = drawableToBitmap(drawable)
        if (maxSize != null) {
            val scale = minOf(maxSize.toFloat() / bitmap.width, maxSize.toFloat() / bitmap.height, 1f)
            if (scale < 1f) {
                val scaledWidth = (bitmap.width * scale).roundToInt().coerceAtLeast(1)
                val scaledHeight = (bitmap.height * scale).roundToInt().coerceAtLeast(1)
                bitmap = Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)
            }
        }
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
