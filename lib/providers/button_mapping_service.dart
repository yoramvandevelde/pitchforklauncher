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

import 'dart:collection';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart';

class ButtonMapping {
  final int keyCode;
  final String label;
  final String packageName;

  ButtonMapping(this.keyCode, this.label, this.packageName);
}

class ButtonMappingService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  List<ButtonMapping> _mappings = [];

  List<ButtonMapping> get mappings => UnmodifiableListView(_mappings);

  ButtonMappingService(this._fLauncherChannel) {
    _refresh();
  }

  Future<void> _refresh() async {
    final raw = await _fLauncherChannel.getButtonMappings();
    _mappings = raw
        .map((e) => ButtonMapping(e["keyCode"] as int, e["label"] as String, e["packageName"] as String))
        .toList();
    notifyListeners();
  }

  /// Emits the keycode/label of the next remote button press, for the "press a button to map
  /// it" capture flow. See `HomeButtonAccessibilityService`/`ButtonCapture` on the native side.
  Stream<Map<dynamic, dynamic>> captureNextButton() => _fLauncherChannel.captureNextButton();

  Future<void> setMapping(int keyCode, String packageName) async {
    await _fLauncherChannel.setButtonMapping(keyCode, packageName);
    await _refresh();
  }

  Future<void> removeMapping(int keyCode) async {
    await _fLauncherChannel.removeButtonMapping(keyCode);
    await _refresh();
  }
}
