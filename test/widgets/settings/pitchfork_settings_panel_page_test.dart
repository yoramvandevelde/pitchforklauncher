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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/button_mapping_panel_page.dart';
import 'package:flauncher/widgets/settings/pitchfork_settings_panel_page.dart';
import 'package:flauncher/widgets/settings/tv_inputs_panel_page.dart';
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
    // Scale down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("'TV Inputs' navigates to TvInputsPanelPage", (tester) async {
    final settingsService = MockSettingsService();
    final appsService = MockAppsService();
    when(settingsService.use24HourTimeFormat).thenReturn(false);
    when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, settingsService, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(Key("TvInputsPanelPage")), findsOneWidget);
  });

  testWidgets("'Set as Home button target' calls AppsService", (
    tester,
  ) async {
    final settingsService = MockSettingsService();
    final appsService = MockAppsService();
    when(settingsService.use24HourTimeFormat).thenReturn(false);
    when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, settingsService, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(appsService.openAccessibilitySettings());
  });

  testWidgets("'Remote buttons' opens ButtonMappingPanelPage", (
    tester,
  ) async {
    final settingsService = MockSettingsService();
    final appsService = MockAppsService();
    when(settingsService.use24HourTimeFormat).thenReturn(false);
    when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, settingsService, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(Key("ButtonMappingPanelPage")), findsOneWidget);
  });

  testWidgets("'Use 24-hour time format' toggle calls SettingsService", (
    tester,
  ) async {
    final settingsService = MockSettingsService();
    final appsService = MockAppsService();
    when(settingsService.use24HourTimeFormat).thenReturn(false);
    when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, settingsService, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    verify(settingsService.setUse24HourTimeFormat(true));
  });

  testWidgets(
    "'App card highlight animation' toggle calls SettingsService",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

      await _pumpWidgetWithProviders(tester, settingsService, appsService);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verify(settingsService.setAppHighlightAnimationEnabled(false));
    },
  );

  testWidgets(
    "'Backup' calls SettingsBackupService after confirmation",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(true));
      when(
        backupService.exportSettings(),
      ).thenAnswer((_) => Future.value());

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Back up settings?"), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verify(backupService.exportSettings());
      expect(find.text("Backed up"), findsOneWidget);
    },
  );

  testWidgets(
    "'Backup' can be cancelled from the confirmation dialog",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(true));
      when(
        backupService.exportSettings(),
      ).thenAnswer((_) => Future.value());

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Back up settings?"), findsOneWidget);

      // Cancel is already focused because of autofocus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verifyNever(backupService.exportSettings());
      expect(find.text("Back up settings?"), findsNothing);
    },
  );

  testWidgets(
    "'Restore' calls SettingsBackupService after confirmation",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(true));
      when(backupService.importSettings()).thenAnswer((_) => Future.value());

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Restore settings?"), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verify(backupService.importSettings());
      expect(find.text("Restored"), findsOneWidget);
    },
  );

  testWidgets(
    "'Restore' can be cancelled from the confirmation dialog",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(true));
      when(backupService.importSettings()).thenAnswer((_) => Future.value());

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Restore settings?"), findsOneWidget);

      // Cancel is already focused because of autofocus.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verifyNever(backupService.importSettings());
      expect(find.text("Restore settings?"), findsNothing);
    },
  );

  testWidgets(
    "'Backup' prompts to grant access instead of the confirmation dialog "
    "when storage isn't available",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(false));
      when(
        backupService.isStorageSupported(),
      ).thenAnswer((_) => Future.value(true));
      when(
        backupService.openStoragePermissionSettings(),
      ).thenAnswer((_) => Future.value(true));

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Back up settings?"), findsNothing);
      expect(find.text('Needs "All files access"'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      verify(backupService.openStoragePermissionSettings());
      verifyNever(backupService.exportSettings());
    },
  );

  testWidgets(
    "'Backup' shows an unsupported message instead of the grant-access "
    "dialog when the OS is too old",
    (tester) async {
      final settingsService = MockSettingsService();
      final appsService = MockAppsService();
      final backupService = MockSettingsBackupService();
      when(settingsService.use24HourTimeFormat).thenReturn(false);
      when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
      when(
        backupService.isStorageAvailable(),
      ).thenAnswer((_) => Future.value(false));
      when(
        backupService.isStorageSupported(),
      ).thenAnswer((_) => Future.value(false));

      await _pumpWidgetWithProviders(
        tester,
        settingsService,
        appsService,
        settingsBackupService: backupService,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text("Back up settings?"), findsNothing);
      expect(find.text('Needs "All files access"'), findsNothing);
      expect(find.text("Not supported"), findsOneWidget);

      verifyNever(backupService.openStoragePermissionSettings());
      verifyNever(backupService.exportSettings());
    },
  );
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  SettingsService settingsService,
  AppsService appsService, {
  SettingsBackupService? settingsBackupService,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        Provider<SettingsBackupService>.value(
          value: settingsBackupService ?? MockSettingsBackupService(),
        ),
      ],
      builder: (_, _) => MaterialApp(
        routes: {
          TvInputsPanelPage.routeName: (_) =>
              Container(key: Key("TvInputsPanelPage")),
          ButtonMappingPanelPage.routeName: (_) =>
              Container(key: Key("ButtonMappingPanelPage")),
        },
        home: Material(child: PitchforkSettingsPanelPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
