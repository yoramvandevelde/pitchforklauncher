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

import 'dart:async';

import 'package:flauncher/actions.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/wallpaper_control_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("'Random' has default focus", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService());

    expect(Focus.of(tester.element(find.text("Random"))).hasFocus, isTrue);
  });

  testWidgets("'Random' calls randomFromPicsum, not reapplyPicsumFilters", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService());

    await tester.tap(find.text("Random"));
    await tester.pumpAndSettle();

    verify(wallpaperService.randomFromPicsum());
    verifyNever(wallpaperService.reapplyPicsumFilters(grayscale: anyNamed("grayscale"), blur: anyNamed("blur")));
  });

  testWidgets("switches reflect the service's current filter state", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService(), grayscale: true, blurEnabled: true);

    for (final switchWidget in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(switchWidget.value, isTrue);
    }
  });

  testWidgets("toggling 'Black & White' calls reapplyPicsumFilters", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService());

    await tester.tap(find.byType(Switch).at(0)); // Black & White is the first switch
    await tester.pumpAndSettle();

    verify(wallpaperService.reapplyPicsumFilters(grayscale: true, blur: null));
  });

  testWidgets("toggling 'Blur' calls reapplyPicsumFilters", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService());

    await tester.tap(find.byType(Switch).at(1)); // Blur is the second switch
    await tester.pumpAndSettle();

    verify(wallpaperService.reapplyPicsumFilters(grayscale: false, blur: 4));
  });

  testWidgets("toggling Blur while Black & White is already on combines both in one call", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService(), grayscale: true);

    await tester.tap(find.byType(Switch).at(1)); // Blur is the second switch
    await tester.pumpAndSettle();

    verify(wallpaperService.reapplyPicsumFilters(grayscale: true, blur: 4));
  });

  testWidgets("Back closes only the control bar, not the launcher", (tester) async {
    final wallpaperService = MockWallpaperService();
    final appsService = MockAppsService();
    when(appsService.isDefaultLauncher()).thenAnswer((_) => Future.value(true));

    await _pumpWithControlBar(tester, wallpaperService, appsService);
    expect(find.byType(WallpaperControlBar), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();

    expect(find.byType(WallpaperControlBar), findsNothing);
    verifyNever(appsService.isDefaultLauncher());
  });

  testWidgets("Black & White and Blur are disabled before any photo has been fetched", (tester) async {
    final wallpaperService = MockWallpaperService();
    await _pumpWithControlBar(tester, wallpaperService, MockAppsService(), hasCurrentPicsumPhoto: false);

    for (final switchWidget in tester.widgetList<Switch>(find.byType(Switch))) {
      expect(switchWidget.onChanged, isNull);
    }
  });
}

Future<void> _pumpWithControlBar(
  WidgetTester tester,
  WallpaperService wallpaperService,
  AppsService appsService, {
  bool hasCurrentPicsumPhoto = true,
  bool grayscale = false,
  bool blurEnabled = false,
}) async {
  when(wallpaperService.hasCurrentPicsumPhoto).thenReturn(hasCurrentPicsumPhoto);
  when(wallpaperService.picsumGrayscale).thenReturn(grayscale);
  when(wallpaperService.picsumBlurEnabled).thenReturn(blurEnabled);
  // Replicates flauncher_app.dart's real root BackIntent binding (remote's back-equivalent key ->
  // BackIntent -> systemNavigator:true, which runs the launcher-exit check) so a test can prove
  // the control bar's own Actions binding intercepts BackIntent first and never reaches this root.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
      ],
      builder: (_, _) => MaterialApp(
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          SingleActivator(LogicalKeyboardKey.gameButtonB): PrioritizedIntents(orderedIntents: [
            DismissIntent(),
            BackIntent(),
          ]),
        },
        home: Builder(
          builder: (context) => Actions(
            actions: {BackIntent: BackAction(context, systemNavigator: true)},
            child: Scaffold(body: Container(key: Key("Home"))),
          ),
        ),
      ),
    ),
  );
  final homeContext = tester.element(find.byKey(Key("Home")));
  unawaited(Navigator.of(homeContext, rootNavigator: true).push(WallpaperControlBar.route()));
  await tester.pumpAndSettle();
}
