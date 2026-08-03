/*
 * PitchforkLauncher
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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsBackupService {
  static const _backupVersion = 1;
  static const _latestBackupFileName =
      'pitchfork_launcher_settings_latest.json';

  final SharedPreferences _sharedPreferences;
  final FLauncherDatabase _database;
  final SettingsService _settingsService;
  final WallpaperService _wallpaperService;
  final FLauncherChannel _fLauncherChannel;
  final Future<Directory?> Function() _directoryProvider;

  SettingsBackupService(
    this._sharedPreferences,
    this._database,
    this._settingsService,
    this._wallpaperService,
    this._fLauncherChannel, {
    Future<Directory?> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getExternalStorageDirectory;

  Future<File> exportSettings() async {
    final data = await _buildBackupJson();
    final directory = await _directoryProvider();
    if (directory == null) {
      throw BackupException('External storage is not available');
    }

    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final fileName = 'pitchfork_launcher_settings_$timestamp.json';
    final file = File('${directory.path}/$fileName');
    final latestFile = File('${directory.path}/$_latestBackupFileName');

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    await file.writeAsString(jsonString);
    await latestFile.writeAsString(jsonString);

    return file;
  }

  Future<void> importSettings() async {
    final directory = await _directoryProvider();
    if (directory == null) {
      throw BackupException('External storage is not available');
    }

    final file = File('${directory.path}/$_latestBackupFileName');
    if (!await file.exists()) {
      throw BackupException('Backup file not found: ${file.path}');
    }

    final jsonString = await file.readAsString();
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    final version = data['version'] as int?;
    if (version != _backupVersion) {
      throw BackupException('Unsupported backup version: $version');
    }

    await _restoreFromBackup(data);
  }

  Future<Map<String, dynamic>> _buildBackupJson() async {
    final categoriesWithApps = await _database.listCategoriesWithVisibleApps();
    final allApps = await _database.listApplications();
    final hiddenApps = allApps
        .where((app) => app.hidden)
        .map((app) => app.packageName)
        .toList();
    final buttonMappings = await _fLauncherChannel.getButtonMappings();
    final wallpaperBytes = _wallpaperService.wallpaperBytes;

    return {
      'version': _backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': {
        'use24HourTimeFormat': _settingsService.use24HourTimeFormat,
        'appHighlightAnimationEnabled':
            _settingsService.appHighlightAnimationEnabled,
        'gradientUuid': _settingsService.gradientUuid,
        'picsumPhotoId': _settingsService.picsumPhotoId,
        'picsumGrayscale': _settingsService.picsumGrayscale,
        'picsumBlur': _settingsService.picsumBlur,
      },
      'categories': categoriesWithApps
          .map(
            (categoryWithApps) => {
              'name': categoryWithApps.category.name,
              'sort': categoryWithApps.category.sort.name,
              'type': categoryWithApps.category.type.name,
              'rowHeight': categoryWithApps.category.rowHeight,
              'columnsCount': categoryWithApps.category.columnsCount,
              'order': categoryWithApps.category.order,
              'apps': categoryWithApps.applications
                  .map((app) => app.packageName)
                  .toList(),
            },
          )
          .toList(),
      'hiddenApps': hiddenApps,
      'buttonMappings': buttonMappings,
      'wallpaperBytesBase64': wallpaperBytes != null
          ? base64Encode(wallpaperBytes)
          : null,
    };
  }

  Future<void> _restoreFromBackup(Map<String, dynamic> data) async {
    final settingsMap = data['settings'] as Map<String, dynamic>;
    final categoriesJson = data['categories'] as List<dynamic>;
    final hiddenApps = (data['hiddenApps'] as List<dynamic>).cast<String>();
    final buttonMappings = (data['buttonMappings'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final wallpaperBytesBase64 = data['wallpaperBytesBase64'] as String?;

    await _database.transaction(() async {
      await _database.delete(_database.categories).go();

      final categoryIds = <int>[];
      for (final categoryJson in categoriesJson) {
        final inserted = await _database
            .into(_database.categories)
            .insertReturning(
              CategoriesCompanion.insert(
                name: categoryJson['name'] as String,
                sort: Value(
                  CategorySort.values.byName(categoryJson['sort'] as String),
                ),
                type: Value(
                  CategoryType.values.byName(categoryJson['type'] as String),
                ),
                rowHeight: Value(categoryJson['rowHeight'] as int),
                columnsCount: Value(categoryJson['columnsCount'] as int),
                order: categoryJson['order'] as int,
              ),
            );
        categoryIds.add(inserted.id);
      }

      for (int i = 0; i < categoriesJson.length; i++) {
        final categoryId = categoryIds[i];
        final appPackageNames = (categoriesJson[i]['apps'] as List<dynamic>)
            .cast<String>();
        final assignments = <AppsCategoriesCompanion>[];
        for (int j = 0; j < appPackageNames.length; j++) {
          assignments.add(
            AppsCategoriesCompanion.insert(
              categoryId: categoryId,
              appPackageName: appPackageNames[j],
              order: j,
            ),
          );
        }
        if (assignments.isNotEmpty) {
          await _database.insertAppsCategories(assignments);
        }
      }

      for (final packageName in hiddenApps) {
        await _database.updateApp(
          packageName,
          const AppsCompanion(hidden: Value(true)),
        );
      }
    });

    await _clearSettings();
    await _settingsService.setUse24HourTimeFormat(
      settingsMap['use24HourTimeFormat'] as bool,
    );
    await _settingsService.setAppHighlightAnimationEnabled(
      settingsMap['appHighlightAnimationEnabled'] as bool,
    );
    final gradientUuid = settingsMap['gradientUuid'] as String?;
    if (gradientUuid != null) {
      await _settingsService.setGradientUuid(gradientUuid);
    }
    await _settingsService.setPicsumPhotoId(
      settingsMap['picsumPhotoId'] as int?,
    );
    await _settingsService.setPicsumGrayscale(
      settingsMap['picsumGrayscale'] as bool,
    );
    await _settingsService.setPicsumBlur(settingsMap['picsumBlur'] as int?);

    final existingMappings = await _fLauncherChannel.getButtonMappings();
    for (final mapping in existingMappings) {
      await _fLauncherChannel.removeButtonMapping(mapping['keyCode'] as int);
    }
    for (final mapping in buttonMappings) {
      await _fLauncherChannel.setButtonMapping(
        mapping['keyCode'] as int,
        mapping['packageName'] as String,
      );
    }

    Uint8List? wallpaperBytes;
    if (wallpaperBytesBase64 != null) {
      wallpaperBytes = base64Decode(wallpaperBytesBase64);
    }
    await _wallpaperService.restoreWallpaper(wallpaperBytes);
  }

  Future<void> _clearSettings() async {
    await _sharedPreferences.remove('use_24_hour_time_format');
    await _sharedPreferences.remove('app_highlight_animation_enabled');
    await _sharedPreferences.remove('gradient_uuid');
    await _sharedPreferences.remove('picsum_photo_id');
    await _sharedPreferences.remove('picsum_grayscale');
    await _sharedPreferences.remove('picsum_blur');
  }
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => message;
}
