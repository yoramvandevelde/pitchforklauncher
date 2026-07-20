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

import 'package:flauncher/actions.dart';
import 'package:flauncher/picsum_service.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/ticker_model.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'flauncher.dart';
import 'flauncher_channel.dart';

// Defensive guard against overlapping pop attempts, matching the guard in settings_panel.dart --
// the same class of bug (PopScope's onPopInvokedWithResult re-entering on rapid repeated Back
// presses) was confirmed there via a real ANR (see UPGRADE_PLAN.md's Phase 4 landmines). This
// root-level scope wasn't confirmed to hit it directly, but the risk shape is identical: without
// this, a second Back press could re-run shouldPopScope()/startAmbientMode() before the first
// async round trip finishes.
bool _handlingPop = false;

class FLauncherApp extends StatelessWidget {
  final SharedPreferences _sharedPreferences;
  final ImagePicker _imagePicker;
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _fLauncherDatabase;
  final UnsplashService _unsplashService;
  final PicsumService _picsumService;

  static const MaterialColor _swatch = MaterialColor(0xFF011526, <int, Color>{
    50: Color(0xFF36A0FA),
    100: Color(0xFF067BDE),
    200: Color(0xFF045CA7),
    300: Color(0xFF033662),
    400: Color(0xFF022544),
    500: Color(0xFF011526),
    600: Color(0xFF000508),
    700: Color(0xFF000000),
    800: Color(0xFF000000),
    900: Color(0xFF000000),
  });

  FLauncherApp(
    this._sharedPreferences,
    this._imagePicker,
    this._fLauncherChannel,
    this._fLauncherDatabase,
    this._unsplashService,
    this._picsumService,
  );

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsService(_sharedPreferences), lazy: false),
          ChangeNotifierProvider(create: (_) => AppsService(_fLauncherChannel, _fLauncherDatabase)),
          ChangeNotifierProvider(create: (_) => ButtonMappingService(_fLauncherChannel)),
          ChangeNotifierProxyProvider<SettingsService, WallpaperService>(
              create: (_) => WallpaperService(_imagePicker, _fLauncherChannel, _unsplashService, _picsumService),
              update: (_, settingsService, wallpaperService) => wallpaperService!..settingsService = settingsService),
          Provider<TickerModel>(create: (context) => TickerModel(null))
        ],
        child: MaterialApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.gameButtonB): PrioritizedIntents(orderedIntents: [
              DismissIntent(),
              BackIntent(),
            ]),
          },
          actions: {
            ...WidgetsApp.defaultActions,
            DirectionalFocusIntent: SoundFeedbackDirectionalFocusAction(context),
          },
          title: 'FLauncher',
          theme: ThemeData(
            // Material 3 became the default with Flutter 3.16. Pinned to false to keep the
            // existing look exactly as-is during the SDK upgrade -- adopting Material 3 is a
            // deliberate design decision to make separately, not a side effect of this bump.
            useMaterial3: false,
            brightness: Brightness.dark,
            primarySwatch: _swatch,
            colorScheme: ColorScheme.fromSwatch(primarySwatch: _swatch, brightness: Brightness.dark)
                .copyWith(secondary: _swatch[200], surface: _swatch[400]),
            cardColor: _swatch[300],
            canvasColor: _swatch[300],
            dialogTheme: DialogThemeData(backgroundColor: _swatch[400]),
            scaffoldBackgroundColor: _swatch[400],
            textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Colors.white)),
            appBarTheme: AppBarTheme(elevation: 0, backgroundColor: Colors.transparent),
            typography: Typography.material2018(),
            inputDecorationTheme: InputDecorationTheme(
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              labelStyle: Typography.material2018().white.bodyMedium,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: _swatch[200],
              selectionHandleColor: _swatch[200],
            ),
          ),
          home: Builder(
            builder: (context) => PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop || _handlingPop) {
                  return;
                }
                _handlingPop = true;
                try {
                  final shouldPop = await shouldPopScope(context);
                  if (shouldPop) {
                    SystemNavigator.pop();
                  } else {
                    context.read<AppsService>().startAmbientMode();
                  }
                } finally {
                  _handlingPop = false;
                }
              },
              child: Actions(actions: {BackIntent: BackAction(context, systemNavigator: true)}, child: FLauncher()),
            ),
          ),
        ),
      );
}
