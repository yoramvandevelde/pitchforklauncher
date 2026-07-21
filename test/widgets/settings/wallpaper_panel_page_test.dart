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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/settings/gradient_panel_page.dart';
import 'package:flauncher/widgets/settings/unsplash_panel_page.dart';
import 'package:flauncher/widgets/settings/wallpaper_panel_page.dart';
import 'package:flauncher/widgets/wallpaper_control_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("'Unsplash' navigates to UnsplashPanelPage", (tester) async {
    final settingsService = MockSettingsService();
    final wallpaperService = MockWallpaperService();
    when(settingsService.unsplashEnabled).thenReturn(true);
    when(settingsService.unsplashAuthor).thenReturn('{"username": "John Doe", "link": "https://localhost"}');

    await _pumpWidgetWithProviders(tester, settingsService, wallpaperService);

    expect(find.text("Photo by John Doe on Unsplash"), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(Key("UnsplashPanelPage")), findsOneWidget);
  });

  testWidgets("'Random photo' closes the panel and shows the control bar without fetching a photo yet",
      (tester) async {
    final settingsService = MockSettingsService();
    final wallpaperService = MockWallpaperService();
    when(settingsService.unsplashEnabled).thenReturn(true);
    when(settingsService.unsplashAuthor).thenReturn(null);
    when(wallpaperService.hasCurrentPicsumPhoto).thenReturn(false);

    await _pumpWidgetWithProviders(tester, settingsService, wallpaperService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // The bar itself is responsible for the first fetch (its "Random" control) -- opening it
    // shouldn't have already rolled a photo, since that used to race with the panel-close
    // animation when the first network request happened to be slow.
    verifyNever(wallpaperService.randomFromPicsum());
    expect(find.byType(WallpaperPanelPage), findsNothing);
    expect(find.byType(WallpaperControlBar), findsOneWidget);
  });

  testWidgets("'Gradient' navigates to GradientPanelPage", (tester) async {
    final settingsService = MockSettingsService();
    final wallpaperService = MockWallpaperService();
    when(settingsService.unsplashEnabled).thenReturn(true);
    when(settingsService.unsplashAuthor).thenReturn(null);

    await _pumpWidgetWithProviders(tester, settingsService, wallpaperService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(Key("GradientPanelPage")), findsOneWidget);
  });

  group("'Custom'", () {
    testWidgets("opens file explorer if available", (tester) async {
      final settingsService = MockSettingsService();
      final wallpaperService = MockWallpaperService();
      when(settingsService.unsplashEnabled).thenReturn(true);
      when(settingsService.unsplashAuthor).thenReturn(null);

      await _pumpWidgetWithProviders(tester, settingsService, wallpaperService);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verify(wallpaperService.pickWallpaper());
    });

    testWidgets("shows snack bar if not file explorer available", (tester) async {
      final settingsService = MockSettingsService();
      final wallpaperService = MockWallpaperService();
      when(settingsService.unsplashEnabled).thenReturn(true);
      when(wallpaperService.pickWallpaper()).thenThrow(NoFileExplorerException());
      when(settingsService.unsplashAuthor).thenReturn(null);

      await _pumpWidgetWithProviders(tester, settingsService, wallpaperService);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text("Please install a file explorer in order to pick an image."), findsOneWidget);
    });
  });
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  SettingsService settingsService,
  WallpaperService wallpaperService,
) async {
  // WallpaperPanelPage's "Random photo" button pops the *root* navigator, so it needs a route
  // underneath it to pop back to -- mirroring how it's really nested (SettingsPanel dialog, on
  // top of the home screen) at least one level deep, rather than being MaterialApp's only route.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
      ],
      builder: (_, _) => MaterialApp(
        routes: {
          UnsplashPanelPage.routeName: (_) => Container(key: Key("UnsplashPanelPage")),
          GradientPanelPage.routeName: (_) => Container(key: Key("GradientPanelPage")),
        },
        home: Scaffold(body: Container(key: Key("Home"))),
      ),
    ),
  );
  final homeContext = tester.element(find.byKey(Key("Home")));
  unawaited(Navigator.of(homeContext).push(MaterialPageRoute(builder: (_) => Scaffold(body: WallpaperPanelPage()))));
  await tester.pumpAndSettle();
}
