/*
 * FLauncher
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

import 'dart:async';

import 'package:flutter/services.dart';

class FLauncherChannel {
  static const _methodChannel = MethodChannel('io.sifft.pitchforklauncher/method');
  static const _eventChannel = EventChannel('io.sifft.pitchforklauncher/event');
  static const _buttonCaptureEventChannel = EventChannel('io.sifft.pitchforklauncher/buttonCapture');

  /// [visiblePackageNames] gates which apps get a banner computed natively -- see
  /// MainActivity.kt's getApplications for why (icon is always included regardless).
  Future<List<dynamic>> getApplications(List<String> visiblePackageNames) async =>
      (await _methodChannel.invokeListMethod('getApplications', visiblePackageNames))!;

  /// Fetches just the banner for one app on demand, for when it newly enters a visible category
  /// after a sync already decided it didn't need one (see AppsService.addToCategory).
  Future<Uint8List?> getAppBanner(String packageName) async =>
      await _methodChannel.invokeMethod<Uint8List>('getAppBanner', packageName);

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  Future<void> openSettings() async => await _methodChannel.invokeMethod('openSettings');

  Future<void> openAccessibilitySettings() async =>
      await _methodChannel.invokeMethod('openAccessibilitySettings');

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<void> startAmbientMode() async => await _methodChannel.invokeMethod("startAmbientMode");

  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) =>
      _eventChannel.receiveBroadcastStream().listen((event) => listener(event));

  Future<List<dynamic>> getButtonMappings() async => (await _methodChannel.invokeListMethod('getButtonMappings'))!;

  Future<void> setButtonMapping(int keyCode, String packageName) async => await _methodChannel
      .invokeMethod('setButtonMapping', {"keyCode": keyCode, "packageName": packageName});

  Future<void> removeButtonMapping(int keyCode) async =>
      await _methodChannel.invokeMethod('removeButtonMapping', keyCode);

  /// Listens for a single remote button press and returns its keycode/label, for the
  /// "press a button to map it" capture flow in the Settings panel.
  Stream<Map<dynamic, dynamic>> captureNextButton() =>
      _buttonCaptureEventChannel.receiveBroadcastStream().map((event) => event as Map<dynamic, dynamic>).take(1);

  /// Writes [bytes] to [fileName] in the real, shared Downloads folder, so the settings backup
  /// survives an app uninstall. Returns false if the "All files access" permission (see
  /// [isSettingsBackupStorageAvailable]) isn't granted, or on devices below Android 11 (API 30).
  Future<bool> writeSettingsBackup(String fileName, Uint8List bytes) async =>
      await _methodChannel.invokeMethod<bool>('writeSettingsBackup', {
        "fileName": fileName,
        "bytes": bytes,
      }) ??
      false;

  /// Reads [fileName] back from the shared Downloads folder, or null if it doesn't exist (never
  /// backed up yet), the permission isn't granted, or the device is below Android 11.
  Future<Uint8List?> readSettingsBackup(String fileName) async =>
      await _methodChannel.invokeMethod<Uint8List>('readSettingsBackup', fileName);

  /// Whether the "All files access" (`MANAGE_EXTERNAL_STORAGE`) permission that
  /// [writeSettingsBackup]/[readSettingsBackup] rely on is currently granted.
  Future<bool> isSettingsBackupStorageAvailable() async =>
      await _methodChannel.invokeMethod<bool>(
        'isSettingsBackupStorageAvailable',
      ) ??
      false;

  /// Whether backup/restore can work on this OS version at all -- the underlying API needs
  /// Android 11 (API 30), but this app's minSdk is 24. Distinct from
  /// [isSettingsBackupStorageAvailable]: that can be false either because the permission just
  /// isn't granted yet (fixable by the user) or because the device is too old (not fixable), and
  /// the UI needs to tell those two apart to avoid offering a "grant it" action that can't work.
  Future<bool> isSettingsBackupStorageSupported() async =>
      await _methodChannel.invokeMethod<bool>(
        'isSettingsBackupStorageSupported',
      ) ??
      false;

  /// Opens the system Settings screen where the user grants/revokes "All files access" for this
  /// app. Returns false if the screen couldn't be opened (below Android 11, or no matching
  /// Settings activity on this OEM build) instead of throwing.
  Future<bool> openSettingsBackupStoragePermission() async =>
      await _methodChannel.invokeMethod<bool>(
        'openSettingsBackupStoragePermission',
      ) ??
      false;
}
