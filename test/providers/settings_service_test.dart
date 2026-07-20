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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  });

  test("setUse24HourTimeFormat", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setUse24HourTimeFormat(true);

    expect(sharedPreferences.getBool("use_24_hour_time_format"), isTrue);
  });

  test("setGradientUuid", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setGradientUuid("4730aa2d-1a90-49a6-9942-ffe82f470e26");

    expect(sharedPreferences.getString("gradient_uuid"), "4730aa2d-1a90-49a6-9942-ffe82f470e26");
  });

  group("setUnsplashAuthor", () {
    test("with value saves author info", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAuthor("unsplash author");

      expect(sharedPreferences.getString("unsplash_author"), "unsplash author");
    });

    test("without value erases author info", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.setString("unsplash_author", "unsplash author");
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAuthor(null);

      expect(sharedPreferences.getString("unsplash_author"), isNull);
    });
  });

  group("unsplashEnabled", () {
    test("is false without an access key", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.unsplashEnabled, isFalse);
    });

    test("is true with an access key", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.setString("unsplash_access_key", "some-access-key");
      final settingsService = SettingsService(sharedPreferences);

      expect(settingsService.unsplashEnabled, isTrue);
    });
  });

  group("setUnsplashAccessKey", () {
    test("with value saves the access key", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAccessKey("some-access-key");

      expect(sharedPreferences.getString("unsplash_access_key"), "some-access-key");
    });

    test("without value erases the access key", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.setString("unsplash_access_key", "some-access-key");
      final settingsService = SettingsService(sharedPreferences);

      await settingsService.setUnsplashAccessKey(null);

      expect(sharedPreferences.getString("unsplash_access_key"), isNull);
    });
  });

  test("unsplashAuthor", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.setString("unsplash_author", "unsplash author");
    final settingsService = SettingsService(sharedPreferences);

    final unsplashAuthor = settingsService.unsplashAuthor;

    expect(unsplashAuthor, "unsplash author");
  });

  group("getGradientUuid", () {
    test("without uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, null);
    });

    test("with uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      sharedPreferences.setString("gradient_uuid", "4730aa2d-1a90-49a6-9942-ffe82f470e26");
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, "4730aa2d-1a90-49a6-9942-ffe82f470e26");
    });
  });

  group("getUse24HourTimeFormat", () {
    test("without value from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      final use24HourTimeFormat = settingsService.use24HourTimeFormat;

      expect(use24HourTimeFormat, isTrue);
    });

    test("with value from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      sharedPreferences.setBool("use_24_hour_time_format", false);
      final settingsService = SettingsService(sharedPreferences);

      final use24HourTimeFormat = settingsService.use24HourTimeFormat;

      expect(use24HourTimeFormat, isFalse);
    });
  });
}
