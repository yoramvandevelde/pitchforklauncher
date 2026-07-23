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
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unsplash_client/unsplash_client.dart';

import 'flauncher_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open Sans (assets/fonts/) is a bundled asset, not a pub dependency, so Flutter's automatic
  // per-package license collection (the "VIEW LICENSES" screen in FLauncherAboutDialog) doesn't
  // pick it up on its own -- register it explicitly.
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Open Sans'], license);
  });

  // Not required by the Unsplash License (free to use, attribution merely appreciated), but
  // credited anyway per house convention for bundled assets.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Default wallpaper'],
      'Photo by Wilhelm Gunkel, used under the Unsplash License.',
    );
  });

  runZonedGuarded<void>(() async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final imagePicker = ImagePicker();
    final fLauncherChannel = FLauncherChannel();
    final fLauncherDatabase = FLauncherDatabase(connect());
    final unsplashService = UnsplashService(
      UnsplashClient(
        settings: ClientSettings(
          debug: kDebugMode,
          credentials: AppCredentials(accessKey: "", secretKey: ""),
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
