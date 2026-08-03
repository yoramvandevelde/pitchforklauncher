/*
 * PitchforkLauncher
 * Copyright (C) 2026  Yoram van de Velde
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/settings_backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

void main() {
  late Directory backupDirectory;
  late _MockPathProviderPlatform pathProviderPlatform;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    pathProviderPlatform = _MockPathProviderPlatform();
    PathProviderPlatform.instance = pathProviderPlatform;
  });

  setUp(() async {
    backupDirectory = await Directory.systemTemp.createTemp(
      'pitchfork_backup_test',
    );
    SharedPreferences.setMockInitialValues({});
    when(
      pathProviderPlatform.getExternalStoragePath(),
    ).thenAnswer((_) => Future.value(backupDirectory.path));
  });

  tearDown(() async {
    if (await backupDirectory.exists()) {
      await backupDirectory.delete(recursive: true);
    }
  });

  test(
    "export and import roundtrip restores settings, categories, mappings and wallpaper",
    () async {
      final database = FLauncherDatabase.inMemory();
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final fLauncherChannel = MockFLauncherChannel();

      await database.persistApps([
        AppsCompanion.insert(
          packageName: 'com.app.one',
          name: 'App One',
          version: '1',
        ),
        AppsCompanion.insert(
          packageName: 'com.app.two',
          name: 'App Two',
          version: '1',
        ),
        AppsCompanion.insert(
          packageName: 'com.hidden.app',
          name: 'Hidden App',
          version: '1',
        ),
      ]);
      await database.updateApp(
        'com.hidden.app',
        const AppsCompanion(hidden: Value(true)),
      );

      await database.insertCategory(
        CategoriesCompanion.insert(
          name: 'Streaming',
          type: Value(CategoryType.grid),
          order: 0,
        ),
      );
      final category = await (database.select(
        database.categories,
      )..where((c) => c.name.equals('Streaming'))).getSingle();
      await database.insertAppsCategories([
        AppsCategoriesCompanion.insert(
          categoryId: category.id,
          appPackageName: 'com.app.one',
          order: 0,
        ),
        AppsCategoriesCompanion.insert(
          categoryId: category.id,
          appPackageName: 'com.app.two',
          order: 1,
        ),
      ]);

      await settingsService.setUse24HourTimeFormat(false);
      await settingsService.setAppHighlightAnimationEnabled(false);
      await settingsService.setGradientUuid('gradient-uuid');

      when(
        wallpaperService.wallpaperBytes,
      ).thenReturn(Uint8List.fromList([0x01, 0x02, 0x03]));
      when(fLauncherChannel.getButtonMappings()).thenAnswer(
        (_) => Future.value([
          {
            'keyCode': 190,
            'label': 'YouTube',
            'packageName': 'com.google.android.youtube',
          },
        ]),
      );

      final backupService = SettingsBackupService(
        sharedPreferences,
        database,
        settingsService,
        wallpaperService,
        fLauncherChannel,
      );

      final exportedFile = await backupService.exportSettings();

      expect(await exportedFile.exists(), isTrue);
      final latestFile = File(
        '${backupDirectory.path}/pitchfork_launcher_settings_latest.json',
      );
      expect(await latestFile.exists(), isTrue);

      // Mutate everything before importing.
      await database.delete(database.categories).go();
      await database.insertCategory(
        CategoriesCompanion.insert(name: 'Other', order: 0),
      );
      await database.updateApp(
        'com.hidden.app',
        const AppsCompanion(hidden: Value(false)),
      );
      await settingsService.setUse24HourTimeFormat(true);
      await settingsService.setAppHighlightAnimationEnabled(true);
      await settingsService.setGradientUuid('other-gradient');
      when(
        wallpaperService.wallpaperBytes,
      ).thenReturn(Uint8List.fromList([0xFF]));

      final capturedMappings = <Map<String, dynamic>>[];
      final removedKeyCodes = <int>[];
      when(fLauncherChannel.getButtonMappings()).thenAnswer(
        (_) => Future.value([
          {'keyCode': 999, 'label': 'Old', 'packageName': 'com.old'},
        ]),
      );
      when(fLauncherChannel.removeButtonMapping(any)).thenAnswer((invocation) {
        removedKeyCodes.add(invocation.positionalArguments[0] as int);
        return Future.value();
      });
      when(fLauncherChannel.setButtonMapping(any, any)).thenAnswer((
        invocation,
      ) {
        capturedMappings.add({
          'keyCode': invocation.positionalArguments[0] as int,
          'packageName': invocation.positionalArguments[1] as String,
        });
        return Future.value();
      });

      Uint8List? restoredWallpaper;
      when(wallpaperService.restoreWallpaper(any)).thenAnswer((invocation) {
        restoredWallpaper = invocation.positionalArguments[0] as Uint8List?;
        return Future.value();
      });

      await backupService.importSettings();

      final restoredCategories = await database
          .select(database.categories)
          .get();
      expect(restoredCategories.length, 1);
      expect(restoredCategories.first.name, 'Streaming');
      expect(restoredCategories.first.type, CategoryType.grid);

      final restoredAssignments = await database
          .select(database.appsCategories)
          .get();
      expect(restoredAssignments.length, 2);
      expect(restoredAssignments.map((a) => a.appPackageName).toList(), [
        'com.app.one',
        'com.app.two',
      ]);

      final hiddenApp = await (database.select(
        database.apps,
      )..where((a) => a.packageName.equals('com.hidden.app'))).getSingle();
      expect(hiddenApp.hidden, isTrue);

      expect(settingsService.use24HourTimeFormat, isFalse);
      expect(settingsService.appHighlightAnimationEnabled, isFalse);
      expect(settingsService.gradientUuid, 'gradient-uuid');

      expect(removedKeyCodes, [999]);
      expect(capturedMappings, [
        {'keyCode': 190, 'packageName': 'com.google.android.youtube'},
      ]);

      expect(restoredWallpaper, Uint8List.fromList([0x01, 0x02, 0x03]));

      await database.close();
    },
  );

  test("import without wallpaper restores gradient wallpaper", () async {
    final database = FLauncherDatabase.inMemory();
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final fLauncherChannel = MockFLauncherChannel();

    await database.persistApps([
      AppsCompanion.insert(
        packageName: 'com.app.one',
        name: 'App One',
        version: '1',
      ),
    ]);

    await settingsService.setGradientUuid('saved-gradient');

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(
      fLauncherChannel.getButtonMappings(),
    ).thenAnswer((_) => Future.value([]));
    when(
      fLauncherChannel.removeButtonMapping(any),
    ).thenAnswer((_) => Future.value());
    when(
      fLauncherChannel.setButtonMapping(any, any),
    ).thenAnswer((_) => Future.value());

    final backupService = SettingsBackupService(
      sharedPreferences,
      database,
      settingsService,
      wallpaperService,
      fLauncherChannel,
    );

    await backupService.exportSettings();

    Uint8List? restoredWallpaper;
    when(wallpaperService.restoreWallpaper(any)).thenAnswer((invocation) {
      restoredWallpaper = invocation.positionalArguments[0] as Uint8List?;
      return Future.value();
    });

    await backupService.importSettings();

    expect(restoredWallpaper, isNull);

    await database.close();
  });

  test("throws when backup file is missing", () async {
    final database = FLauncherDatabase.inMemory();
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final fLauncherChannel = MockFLauncherChannel();

    final backupService = SettingsBackupService(
      sharedPreferences,
      database,
      settingsService,
      wallpaperService,
      fLauncherChannel,
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test("throws on unsupported backup version", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final database = FLauncherDatabase.inMemory();
    final file = File(
      '${backupDirectory.path}/pitchfork_launcher_settings_latest.json',
    );
    await file.writeAsString(jsonEncode({'version': 99}));

    final backupService = SettingsBackupService(
      sharedPreferences,
      database,
      SettingsService(sharedPreferences),
      MockWallpaperService(),
      MockFLauncherChannel(),
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });
}

class _MockPathProviderPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getExternalStoragePath() => super.noSuchMethod(
    Invocation.method(#getExternalStoragePath, []),
    returnValue: Future<String?>.value(),
  );
}
