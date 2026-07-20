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

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/picsum_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unsplash_client/unsplash_client.dart';

import 'flauncher_app.dart';

// Phase 2 stopgap for manually testing the Unsplash integration ahead of settings UI support
// (TODO.md): pass a real value via --dart-define at build time, never commit it. Used as a
// fallback default only when the user hasn't saved a key via the settings UI yet. Only the access
// key is needed -- AppCredentials.secretKey is never read anywhere in the request path (only used
// for OAuth user-login flows this app doesn't do), so it's omitted.
const _unsplashAccessKeyFallback = String.fromEnvironment("UNSPLASH_ACCESS_KEY");

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runZonedGuarded<void>(() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final imagePicker = ImagePicker();
    final fLauncherChannel = FLauncherChannel();
    final fLauncherDatabase = FLauncherDatabase(connect());
    final storedUnsplashAccessKey = SettingsService(sharedPreferences).unsplashAccessKey;
    final unsplashService = UnsplashService(
      UnsplashClient(
        settings: ClientSettings(
          debug: kDebugMode,
          credentials: AppCredentials(
            accessKey: (storedUnsplashAccessKey?.isNotEmpty ?? false)
                ? storedUnsplashAccessKey!
                : _unsplashAccessKeyFallback,
          ),
        ),
      ),
    );
    final picsumService = PicsumService();
    runApp(
      FLauncherApp(
        sharedPreferences,
        imagePicker,
        fLauncherChannel,
        fLauncherDatabase,
        unsplashService,
        picsumService,
      ),
    );
  }, (error, stackTrace) => debugPrint("$error\n$stackTrace"));
}
