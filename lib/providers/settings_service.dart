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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _use24HourTimeFormatKey = "use_24_hour_time_format";
const _appHighlightAnimationEnabledKey = "app_highlight_animation_enabled";
const _gradientUuidKey = "gradient_uuid";
const _picsumPhotoIdKey = "picsum_photo_id";
const _picsumGrayscaleKey = "picsum_grayscale";
const _picsumBlurKey = "picsum_blur";

class SettingsService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;

  bool get use24HourTimeFormat => _sharedPreferences.getBool(_use24HourTimeFormatKey) ?? true;

  bool get appHighlightAnimationEnabled => _sharedPreferences.getBool(_appHighlightAnimationEnabledKey) ?? true;

  String? get gradientUuid => _sharedPreferences.getString(_gradientUuidKey);

  int? get picsumPhotoId => _sharedPreferences.getInt(_picsumPhotoIdKey);

  bool get picsumGrayscale => _sharedPreferences.getBool(_picsumGrayscaleKey) ?? false;

  int? get picsumBlur => _sharedPreferences.getInt(_picsumBlurKey);

  SettingsService(this._sharedPreferences);

  Future<void> setUse24HourTimeFormat(bool value) async {
    await _sharedPreferences.setBool(_use24HourTimeFormatKey, value);
    notifyListeners();
  }

  Future<void> setAppHighlightAnimationEnabled(bool value) async {
    await _sharedPreferences.setBool(_appHighlightAnimationEnabledKey, value);
    notifyListeners();
  }

  Future<void> setGradientUuid(String value) async {
    await _sharedPreferences.setString(_gradientUuidKey, value);
    notifyListeners();
  }

  Future<void> setPicsumPhotoId(int? value) async {
    if (value == null) {
      await _sharedPreferences.remove(_picsumPhotoIdKey);
    } else {
      await _sharedPreferences.setInt(_picsumPhotoIdKey, value);
    }
    notifyListeners();
  }

  Future<void> setPicsumGrayscale(bool value) async {
    await _sharedPreferences.setBool(_picsumGrayscaleKey, value);
    notifyListeners();
  }

  Future<void> setPicsumBlur(int? value) async {
    if (value == null) {
      await _sharedPreferences.remove(_picsumBlurKey);
    } else {
      await _sharedPreferences.setInt(_picsumBlurKey, value);
    }
    notifyListeners();
  }
}
