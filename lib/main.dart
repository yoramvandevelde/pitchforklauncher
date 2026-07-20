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
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unsplash_client/unsplash_client.dart';

import 'flauncher_app.dart';

// Phase 2 stopgap for manually testing the Unsplash integration before the settings UI (TODO.md)
// exists to store a user-supplied key: pass real values via --dart-define at build time, never
// commit them. Empty defaults keep the feature inert (SettingsService.unsplashEnabled is also
// still hardcoded false) when nothing is passed.
const _unsplashAccessKey = String.fromEnvironment("UNSPLASH_ACCESS_KEY");
const _unsplashSecretKey = String.fromEnvironment("UNSPLASH_SECRET_KEY");

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runZonedGuarded<void>(() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final imagePicker = ImagePicker();
    final fLauncherChannel = FLauncherChannel();
    final fLauncherDatabase = FLauncherDatabase(connect());
    final unsplashService = UnsplashService(
      UnsplashClient(
        settings: ClientSettings(
          debug: kDebugMode,
          credentials: AppCredentials(accessKey: _unsplashAccessKey, secretKey: _unsplashSecretKey),
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
