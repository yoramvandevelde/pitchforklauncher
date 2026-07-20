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

  Future<List<dynamic>> getApplications() async => (await _methodChannel.invokeListMethod('getApplications'))!;

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
}
