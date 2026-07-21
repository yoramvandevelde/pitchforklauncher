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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/widgets/settings/button_mapping_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("mappings are displayed", (tester) async {
    final buttonMappingService = MockButtonMappingService();
    final appsService = MockAppsService();
    when(buttonMappingService.mappings)
        .thenReturn([ButtonMapping(190, "KEYCODE_BUTTON_3", "com.google.android.youtube.tv")]);
    when(appsService.applications).thenReturn([
      fakeApp(packageName: "com.google.android.youtube.tv", name: "YouTube"),
    ]);

    await _pumpWidgetWithProviders(tester, buttonMappingService, appsService);

    expect(find.text("YouTube"), findsOneWidget);
    expect(find.text("KEYCODE_BUTTON_3"), findsOneWidget);
  });

  testWidgets("falls back to the package name if the app is unknown", (tester) async {
    final buttonMappingService = MockButtonMappingService();
    final appsService = MockAppsService();
    when(buttonMappingService.mappings)
        .thenReturn([ButtonMapping(190, "KEYCODE_BUTTON_3", "com.google.android.youtube.tv")]);
    when(appsService.applications).thenReturn([]);

    await _pumpWidgetWithProviders(tester, buttonMappingService, appsService);

    expect(find.text("com.google.android.youtube.tv"), findsOneWidget);
  });

  testWidgets("delete icon calls removeMapping", (tester) async {
    final buttonMappingService = MockButtonMappingService();
    final appsService = MockAppsService();
    when(buttonMappingService.mappings)
        .thenReturn([ButtonMapping(190, "KEYCODE_BUTTON_3", "com.google.android.youtube.tv")]);
    when(appsService.applications).thenReturn([]);

    await _pumpWidgetWithProviders(tester, buttonMappingService, appsService);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    verify(buttonMappingService.removeMapping(190));
  });

  testWidgets("'Add mapping' captures a button then sets the mapping from the picked app", (tester) async {
    final buttonMappingService = MockButtonMappingService();
    final appsService = MockAppsService();
    when(buttonMappingService.mappings).thenReturn([]);
    when(appsService.applications).thenReturn([fakeApp(packageName: "com.netflix.ninja", name: "Netflix")]);
    when(buttonMappingService.captureNextButton())
        .thenAnswer((_) => Stream.value({"keyCode": 191, "label": "KEYCODE_BUTTON_4"}));

    await _pumpWidgetWithProviders(tester, buttonMappingService, appsService);
    await tester.tap(find.text("Add mapping"));
    await tester.pumpAndSettle();

    expect(find.text("Netflix"), findsOneWidget);
    await tester.tap(find.text("Netflix"));
    await tester.pumpAndSettle();

    verify(buttonMappingService.setMapping(191, "com.netflix.ninja"));
  });

  testWidgets("'Cancel' in the capture dialog doesn't set a mapping", (tester) async {
    final buttonMappingService = MockButtonMappingService();
    final appsService = MockAppsService();
    when(buttonMappingService.mappings).thenReturn([]);
    when(appsService.applications).thenReturn([]);
    when(buttonMappingService.captureNextButton()).thenAnswer((_) => const Stream.empty());

    await _pumpWidgetWithProviders(tester, buttonMappingService, appsService);
    await tester.tap(find.text("Add mapping"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();

    verifyNever(buttonMappingService.setMapping(any, any));
  });
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  ButtonMappingService buttonMappingService,
  AppsService appsService,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ButtonMappingService>.value(value: buttonMappingService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
      ],
      builder: (_, _) => MaterialApp(
        home: Scaffold(body: ButtonMappingPanelPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
