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

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/providers/settings_backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/tv_input_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mocks.mocks.dart';

void main() {
  // Stands in for the shared Downloads collection that SettingsBackupStorage.kt reads/writes on
  // the Android side (see FLauncherChannel.writeSettingsBackup/readSettingsBackup) -- a plain Map
  // keyed by file name is enough to fake "the file that was last written" for these tests.
  late Map<String, Uint8List> fakeDownloads;
  late MockFLauncherChannel fLauncherChannel;

  setUp(() {
    fakeDownloads = {};
    fLauncherChannel = MockFLauncherChannel();
    when(fLauncherChannel.writeSettingsBackup(any, any))
        .thenAnswer((invocation) {
          fakeDownloads[invocation.positionalArguments[0] as String] =
              invocation.positionalArguments[1] as Uint8List;
          return Future.value(true);
        });
    when(fLauncherChannel.readSettingsBackup(any)).thenAnswer(
      (invocation) => Future.value(
        fakeDownloads[invocation.positionalArguments[0] as String],
      ),
    );
  });

  test("export and import roundtrip restores settings, categories, mappings and wallpaper", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

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
      AppsCompanion.insert(
        packageName: 'com.google.android.youtube',
        name: 'YouTube',
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
        showName: Value(false),
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

    when(wallpaperService.wallpaperBytes)
        .thenReturn(Uint8List.fromList([0x01, 0x02, 0x03]));
    when(
      buttonMappingService.mappings,
    ).thenReturn([ButtonMapping(190, 'YouTube', 'com.google.android.youtube')]);
    when(tvInputService.inputs).thenReturn([
      const TvInputConfig(
        id: 'tv1',
        label: 'Xbox',
        profileId: 'generic',
        params: {'host': '192.168.1.50'},
      ),
    ]);

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
      fLauncherChannel,
    );

    await backupService.exportSettings();

    expect(fakeDownloads[SettingsBackupService.backupFileName], isNotNull);

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
    when(wallpaperService.wallpaperBytes)
        .thenReturn(Uint8List.fromList([0xFF]));

    final capturedMappings = <Map<String, dynamic>>[];
    final removedKeyCodes = <int>[];
    when(buttonMappingService.mappings)
        .thenReturn([ButtonMapping(999, 'Old', 'com.old')]);
    when(buttonMappingService.removeMapping(any)).thenAnswer((invocation) {
      removedKeyCodes.add(invocation.positionalArguments[0] as int);
      return Future.value();
    });
    when(buttonMappingService.setMapping(any, any)).thenAnswer((invocation) {
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
    List<TvInputConfig>? restoredTvInputs;
    when(tvInputService.replaceAll(any)).thenAnswer((invocation) {
      restoredTvInputs =
          invocation.positionalArguments[0] as List<TvInputConfig>;
      return Future.value();
    });
    when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

    await backupService.importSettings();

    final restoredCategories = await database.select(database.categories).get();
    expect(restoredCategories.length, 1);
    expect(restoredCategories.first.name, 'Streaming');
    expect(restoredCategories.first.type, CategoryType.grid);
    expect(restoredCategories.first.showName, false);

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

    expect(restoredTvInputs, hasLength(1));
    expect(restoredTvInputs!.first.id, 'tv1');
    expect(restoredTvInputs!.first.label, 'Xbox');
    expect(restoredTvInputs!.first.profileId, 'generic');
    expect(restoredTvInputs!.first.params, {'host': '192.168.1.50'});

    verify(appsService.reloadFromDatabase());

    await database.close();
  });

  test("import without wallpaper restores gradient wallpaper", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

    await database.persistApps([
      AppsCompanion.insert(
        packageName: 'com.app.one',
        name: 'App One',
        version: '1',
      ),
    ]);

    await settingsService.setGradientUuid('saved-gradient');

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(buttonMappingService.mappings).thenReturn([]);
    when(buttonMappingService.removeMapping(any))
        .thenAnswer((_) => Future.value());
    when(buttonMappingService.setMapping(any, any))
        .thenAnswer((_) => Future.value());
    when(tvInputService.inputs).thenReturn([]);
    when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
    when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
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
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      MockTvInputService(),
      MockAppsService(),
      MockButtonMappingService(),
      fLauncherChannel,
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test("throws on unsupported backup version", () async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final database = FLauncherDatabase.inMemory();
    fakeDownloads[SettingsBackupService.backupFileName] = Uint8List.fromList(
      utf8.encode(jsonEncode({'version': 99})),
    );

    final backupService = SettingsBackupService(
      database,
      SettingsService(sharedPreferences),
      MockWallpaperService(),
      MockTvInputService(),
      MockAppsService(),
      MockButtonMappingService(),
      fLauncherChannel,
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test(
    "import skips apps that are not installed instead of crashing",
    () async {
      final database = FLauncherDatabase.inMemory();
      SharedPreferences.setMockInitialValues({});
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final tvInputService = MockTvInputService();
      final appsService = MockAppsService();
      final buttonMappingService = MockButtonMappingService();

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
      ]);

      await database.insertCategory(
        CategoriesCompanion.insert(name: 'Streaming', order: 0),
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

      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(buttonMappingService.mappings).thenReturn([]);
      when(buttonMappingService.removeMapping(any))
          .thenAnswer((_) => Future.value());
      when(buttonMappingService.setMapping(any, any))
          .thenAnswer((_) => Future.value());
      when(wallpaperService.restoreWallpaper(any))
          .thenAnswer((_) => Future.value());
      when(tvInputService.inputs).thenReturn([]);
      when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
      when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

      final backupService = SettingsBackupService(
        database,
        settingsService,
        wallpaperService,
        tvInputService,
        appsService,
        buttonMappingService,
        fLauncherChannel,
      );

      await backupService.exportSettings();

      // Simulate an app being uninstalled before import.
      await database.deleteApps(['com.app.two']);

      await backupService.importSettings();

      final restoredAssignments = await database
          .select(database.appsCategories)
          .get();
      expect(restoredAssignments.length, 1);
      expect(restoredAssignments.first.appPackageName, 'com.app.one');

      await database.close();
    },
  );

  test("import resets hidden apps before restoring hidden state", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

    await database.persistApps([
      AppsCompanion.insert(
        packageName: 'com.app.one',
        name: 'App One',
        version: '1',
      ),
    ]);

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(buttonMappingService.mappings).thenReturn([]);
    when(buttonMappingService.removeMapping(any))
        .thenAnswer((_) => Future.value());
    when(buttonMappingService.setMapping(any, any))
        .thenAnswer((_) => Future.value());
    when(wallpaperService.restoreWallpaper(any))
        .thenAnswer((_) => Future.value());
    when(tvInputService.inputs).thenReturn([]);
    when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
    when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
      fLauncherChannel,
    );

    await backupService.exportSettings();

    // Hide an app after the backup was made.
    await database.updateApp(
      'com.app.one',
      const AppsCompanion(hidden: Value(true)),
    );

    await backupService.importSettings();

    final restoredApp = await (database.select(
      database.apps,
    )..where((a) => a.packageName.equals('com.app.one'))).getSingle();
    expect(restoredApp.hidden, isFalse);

    await database.close();
  });

  test(
    "a hidden app's category membership survives an export/import roundtrip",
    () async {
      final database = FLauncherDatabase.inMemory();
      SharedPreferences.setMockInitialValues({});
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final tvInputService = MockTvInputService();
      final appsService = MockAppsService();
      final buttonMappingService = MockButtonMappingService();

      await database.persistApps([
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
        CategoriesCompanion.insert(name: 'Streaming', order: 0),
      );
      final category = await (database.select(
        database.categories,
      )..where((c) => c.name.equals('Streaming'))).getSingle();
      await database.insertAppsCategories([
        AppsCategoriesCompanion.insert(
          categoryId: category.id,
          appPackageName: 'com.hidden.app',
          order: 0,
        ),
      ]);

      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(buttonMappingService.mappings).thenReturn([]);
      when(buttonMappingService.removeMapping(any))
          .thenAnswer((_) => Future.value());
      when(buttonMappingService.setMapping(any, any))
          .thenAnswer((_) => Future.value());
      when(wallpaperService.restoreWallpaper(any))
          .thenAnswer((_) => Future.value());
      when(tvInputService.inputs).thenReturn([]);
      when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
      when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

      final backupService = SettingsBackupService(
        database,
        settingsService,
        wallpaperService,
        tvInputService,
        appsService,
        buttonMappingService,
        fLauncherChannel,
      );

      await backupService.exportSettings();
      await backupService.importSettings();

      // Unhide it after the restore -- it should still be in its category, not orphaned.
      await database.updateApp(
        'com.hidden.app',
        const AppsCompanion(hidden: Value(false)),
      );

      final assignments = await database.select(database.appsCategories).get();
      expect(assignments.length, 1);
      expect(assignments.first.appPackageName, 'com.hidden.app');

      await database.close();
    },
  );

  test("throws BackupException on corrupt JSON", () async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final database = FLauncherDatabase.inMemory();
    fakeDownloads[SettingsBackupService.backupFileName] = Uint8List.fromList(
      utf8.encode('not valid json'),
    );

    final backupService = SettingsBackupService(
      database,
      SettingsService(sharedPreferences),
      MockWallpaperService(),
      MockTvInputService(),
      MockAppsService(),
      MockButtonMappingService(),
      fLauncherChannel,
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test("throws BackupException on syntactically valid JSON with the wrong shape", () async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final database = FLauncherDatabase.inMemory();
    // Valid JSON, but missing the 'settings' key entirely -- casting the missing value to
    // Map<String, dynamic> throws a TypeError, not a FormatException/Exception.
    fakeDownloads[SettingsBackupService.backupFileName] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'categories': [],
          'hiddenApps': [],
          'buttonMappings': [],
        }),
      ),
    );

    final backupService = SettingsBackupService(
      database,
      SettingsService(sharedPreferences),
      MockWallpaperService(),
      MockTvInputService(),
      MockAppsService(),
      MockButtonMappingService(),
      fLauncherChannel,
    );

    expect(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test("leaves settings untouched when a category later in the payload has a bad enum value", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setUse24HourTimeFormat(true);

    // Everything parses fine except the category's 'sort' value, which isn't a real
    // CategorySort name. Validating the whole payload up front (rather than only once the
    // database step gets to this category) means the settings restore below should never run.
    fakeDownloads[SettingsBackupService.backupFileName] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'settings': {
            'use24HourTimeFormat': false,
            'appHighlightAnimationEnabled': false,
            'gradientUuid': null,
            'picsumPhotoId': null,
            'picsumGrayscale': false,
            'picsumBlur': null,
          },
          'categories': [
            {
              'name': 'Streaming',
              'sort': 'not_a_real_sort_value',
              'type': 'grid',
              'rowHeight': 110,
              'columnsCount': 6,
              'order': 0,
              'apps': [],
            },
          ],
          'hiddenApps': [],
          'buttonMappings': [],
          'tvInputs': [],
          'wallpaperBytesBase64': null,
        }),
      ),
    );

    final backupService = SettingsBackupService(
      database,
      settingsService,
      MockWallpaperService(),
      MockTvInputService(),
      MockAppsService(),
      MockButtonMappingService(),
      fLauncherChannel,
    );

    await expectLater(
      () => backupService.importSettings(),
      throwsA(isA<BackupException>()),
    );

    expect(settingsService.use24HourTimeFormat, isTrue);

    await database.close();
  });

  test(
    "import skips button mappings pointing at apps that are not installed",
    () async {
      final database = FLauncherDatabase.inMemory();
      SharedPreferences.setMockInitialValues({});
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final tvInputService = MockTvInputService();
      final appsService = MockAppsService();
      final buttonMappingService = MockButtonMappingService();

      await database.persistApps([
        AppsCompanion.insert(
          packageName: 'com.app.one',
          name: 'App One',
          version: '1',
        ),
      ]);

      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(buttonMappingService.mappings).thenReturn([
        ButtonMapping(1, 'One', 'com.app.one'),
        ButtonMapping(2, 'Uninstalled', 'com.not.installed'),
      ]);
      when(buttonMappingService.removeMapping(any))
          .thenAnswer((_) => Future.value());
      final capturedMappings = <Map<String, dynamic>>[];
      when(buttonMappingService.setMapping(any, any)).thenAnswer((invocation) {
        capturedMappings.add({
          'keyCode': invocation.positionalArguments[0] as int,
          'packageName': invocation.positionalArguments[1] as String,
        });
        return Future.value();
      });
      when(wallpaperService.restoreWallpaper(any))
          .thenAnswer((_) => Future.value());
      when(tvInputService.inputs).thenReturn([]);
      when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
      when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

      final backupService = SettingsBackupService(
        database,
        settingsService,
        wallpaperService,
        tvInputService,
        appsService,
        buttonMappingService,
        fLauncherChannel,
      );

      await backupService.exportSettings();

      await backupService.importSettings();

      expect(capturedMappings, [
        {'keyCode': 1, 'packageName': 'com.app.one'},
      ]);

      await database.close();
    },
  );

  test(
    "reloads AppsService from the database after a successful import",
    () async {
      final database = FLauncherDatabase.inMemory();
      SharedPreferences.setMockInitialValues({});
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final tvInputService = MockTvInputService();
      final appsService = MockAppsService();
      final buttonMappingService = MockButtonMappingService();

      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(buttonMappingService.mappings).thenReturn([]);
      when(buttonMappingService.removeMapping(any))
          .thenAnswer((_) => Future.value());
      when(buttonMappingService.setMapping(any, any))
          .thenAnswer((_) => Future.value());
      when(wallpaperService.restoreWallpaper(any))
          .thenAnswer((_) => Future.value());
      when(tvInputService.inputs).thenReturn([]);
      when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
      when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

      final backupService = SettingsBackupService(
        database,
        settingsService,
        wallpaperService,
        tvInputService,
        appsService,
        buttonMappingService,
        fLauncherChannel,
      );

      await backupService.exportSettings();

      verifyNever(appsService.reloadFromDatabase());

      await backupService.importSettings();

      verify(appsService.reloadFromDatabase());

      await database.close();
    },
  );

  test(
    "leaves categories untouched if a step before the database restore fails",
    () async {
      final database = FLauncherDatabase.inMemory();
      SharedPreferences.setMockInitialValues({});
      final sharedPreferences = await SharedPreferences.getInstance();
      final settingsService = SettingsService(sharedPreferences);
      final wallpaperService = MockWallpaperService();
      final tvInputService = MockTvInputService();
      final appsService = MockAppsService();
      final buttonMappingService = MockButtonMappingService();

      await database.persistApps([
        AppsCompanion.insert(
          packageName: 'com.app.one',
          name: 'App One',
          version: '1',
        ),
      ]);
      await database.insertCategory(
        CategoriesCompanion.insert(name: 'Original', order: 0),
      );

      when(wallpaperService.wallpaperBytes).thenReturn(null);
      when(buttonMappingService.mappings).thenReturn([]);
      when(buttonMappingService.removeMapping(any))
          .thenAnswer((_) => Future.value());
      when(buttonMappingService.setMapping(any, any))
          .thenAnswer((_) => Future.value());
      when(wallpaperService.restoreWallpaper(any))
          .thenAnswer((_) => Future.value());
      when(tvInputService.inputs).thenReturn([]);
      when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());

      final backupService = SettingsBackupService(
        database,
        settingsService,
        wallpaperService,
        tvInputService,
        appsService,
        buttonMappingService,
        fLauncherChannel,
      );

      await backupService.exportSettings();

      // Make the wallpaper-restore step (which runs before the database transaction) fail.
      when(wallpaperService.restoreWallpaper(any))
          .thenThrow(Exception('disk full'));

      await expectLater(
        () => backupService.importSettings(),
        throwsA(isA<BackupException>()),
      );

      final categories = await database.select(database.categories).get();
      expect(categories.length, 1);
      expect(categories.first.name, 'Original');

      verifyNever(appsService.reloadFromDatabase());

      await database.close();
    },
  );

  test("throws BackupException when the native side reports the write failed "
      "(e.g. \"All files access\" not granted)", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(buttonMappingService.mappings).thenReturn([]);
    when(tvInputService.inputs).thenReturn([]);
    when(fLauncherChannel.writeSettingsBackup(any, any))
        .thenAnswer((_) => Future.value(false));

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
      fLauncherChannel,
    );

    await expectLater(
      () => backupService.exportSettings(),
      throwsA(isA<BackupException>()),
    );

    await database.close();
  });

  test("export strips a Samsung TV input's pairing token, keeps the rest of its params", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(buttonMappingService.mappings).thenReturn([]);
    when(tvInputService.inputs).thenReturn([
      const TvInputConfig(
        id: 'tv1',
        label: 'Living room TV',
        profileId: 'samsung_tizen',
        params: {
          'host': '192.168.1.50',
          'key': 'KEY_HDMI',
          'token': 'has-replay-value-dont-export-me',
        },
      ),
    ]);

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
      fLauncherChannel,
    );

    await backupService.exportSettings();

    final exported = jsonDecode(
      utf8.decode(fakeDownloads[SettingsBackupService.backupFileName]!),
    ) as Map<String, dynamic>;
    final exportedParams =
        (exported['tvInputs'] as List)[0]['params'] as Map<String, dynamic>;
    expect(exportedParams, {'host': '192.168.1.50', 'key': 'KEY_HDMI'});
    expect(exportedParams.containsKey('token'), isFalse);

    await database.close();
  });

  test("import defaults a category's showName to true when absent (backup predates the field)", () async {
    final database = FLauncherDatabase.inMemory();
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final wallpaperService = MockWallpaperService();
    final tvInputService = MockTvInputService();
    final appsService = MockAppsService();
    final buttonMappingService = MockButtonMappingService();

    when(wallpaperService.wallpaperBytes).thenReturn(null);
    when(buttonMappingService.mappings).thenReturn([]);
    when(buttonMappingService.removeMapping(any))
        .thenAnswer((_) => Future.value());
    when(buttonMappingService.setMapping(any, any))
        .thenAnswer((_) => Future.value());
    when(wallpaperService.restoreWallpaper(any))
        .thenAnswer((_) => Future.value());
    when(tvInputService.inputs).thenReturn([]);
    when(tvInputService.replaceAll(any)).thenAnswer((_) => Future.value());
    when(appsService.reloadFromDatabase()).thenAnswer((_) => Future.value());

    fakeDownloads[SettingsBackupService.backupFileName] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'settings': {
            'use24HourTimeFormat': false,
            'appHighlightAnimationEnabled': false,
            'gradientUuid': null,
            'picsumPhotoId': null,
            'picsumGrayscale': false,
            'picsumBlur': null,
          },
          'categories': [
            {
              'name': 'Streaming',
              'sort': 'manual',
              'type': 'grid',
              'rowHeight': 110,
              'columnsCount': 6,
              'order': 0,
              'apps': [],
              // No 'showName' key -- this is what every backup written before that field
              // existed looks like.
            },
          ],
          'hiddenApps': [],
          'buttonMappings': [],
          'tvInputs': [],
          'wallpaperBytesBase64': null,
        }),
      ),
    );

    final backupService = SettingsBackupService(
      database,
      settingsService,
      wallpaperService,
      tvInputService,
      appsService,
      buttonMappingService,
      fLauncherChannel,
    );

    await backupService.importSettings();

    final restoredCategory = await database
        .select(database.categories)
        .getSingle();
    expect(restoredCategory.showName, true);

    await database.close();
  });
}
