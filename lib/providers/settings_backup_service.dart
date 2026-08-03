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
import 'package:flauncher/providers/tv_input_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:path_provider/path_provider.dart';

class SettingsBackupService {
  static const _backupVersion = 1;
  static const _latestBackupFileName =
      'pitchfork_launcher_settings_latest.json';

  final FLauncherDatabase _database;
  final SettingsService _settingsService;
  final WallpaperService _wallpaperService;
  final FLauncherChannel _fLauncherChannel;
  final TvInputService _tvInputService;
  final Future<Directory?> Function() _directoryProvider;

  SettingsBackupService(
    this._database,
    this._settingsService,
    this._wallpaperService,
    this._fLauncherChannel,
    this._tvInputService, {
    Future<Directory?> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getExternalStorageDirectory;

  Future<File> exportSettings() async {
    try {
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
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Export failed: $e');
    }
  }

  Future<void> importSettings() async {
    try {
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

      // Parsed and validated in full -- including enum names and the wallpaper's base64 -- before
      // any of it is applied. Restoring is spread across several stores (SharedPreferences, the
      // native button-mapping channel, the wallpaper file, the database) with no shared rollback,
      // so a malformed field discovered midway through restoring would leave things part restored,
      // part not. Fail here instead, before anything has been touched.
      final backup = _ParsedBackup.fromJson(data);

      await _restoreFromBackup(backup);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Import failed: $e');
    }
  }

  Future<Map<String, dynamic>> _buildBackupJson() async {
    // Not listCategoriesWithVisibleApps(): a hidden app keeps its category membership row (hiding
    // only flips the app's own `hidden` flag), so using the visible-only query here would silently
    // drop that membership from the backup -- unhiding the app after a restore would then leave it
    // uncategorized even though it never actually lost its category.
    final categoriesWithApps = await _database.listCategoriesWithAllApps();
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
      'tvInputs': _tvInputService.inputs.map((input) => input.toJson()).toList(),
      'wallpaperBytesBase64': wallpaperBytes != null
          ? base64Encode(wallpaperBytes)
          : null,
    };
  }

  /// Restores settings, button mappings, TV inputs and the wallpaper first, then the
  /// categories/apps/hidden state last via the one step that's actually transactional (see
  /// `_database.transaction` below). None of the earlier steps (SharedPreferences, the native
  /// button-mapping channel, the wallpaper file) can be rolled back if a later step fails, so if
  /// anything is going to fail partway through, better it's before the database (the
  /// hardest-to-manually-recreate data: categories and app assignments) has been touched at all,
  /// leaving it in its original state rather than a half-restored one. [backup] has already been
  /// fully parsed and validated by this point (see `_ParsedBackup.fromJson`), so nothing here
  /// should throw due to malformed input -- only due to an actual write failing.
  Future<void> _restoreFromBackup(_ParsedBackup backup) async {
    final installedPackages = (await _database.listApplications())
        .map((app) => app.packageName)
        .toSet();

    await _settingsService.resetToDefaults();
    await _settingsService.setUse24HourTimeFormat(
      backup.use24HourTimeFormat,
    );
    await _settingsService.setAppHighlightAnimationEnabled(
      backup.appHighlightAnimationEnabled,
    );
    final gradientUuid = backup.gradientUuid;
    if (gradientUuid != null) {
      await _settingsService.setGradientUuid(gradientUuid);
    }
    await _settingsService.setPicsumPhotoId(backup.picsumPhotoId);
    await _settingsService.setPicsumGrayscale(backup.picsumGrayscale);
    await _settingsService.setPicsumBlur(backup.picsumBlur);

    final existingMappings = await _fLauncherChannel.getButtonMappings();
    for (final mapping in existingMappings) {
      await _fLauncherChannel.removeButtonMapping(mapping['keyCode'] as int);
    }
    for (final mapping in backup.buttonMappings) {
      if (installedPackages.contains(mapping.packageName)) {
        await _fLauncherChannel.setButtonMapping(
          mapping.keyCode,
          mapping.packageName,
        );
      }
    }

    await _tvInputService.replaceAll(backup.tvInputs);

    await _wallpaperService.restoreWallpaper(backup.wallpaperBytes);

    await _database.transaction(() async {
      await _database.delete(_database.categories).go();
      await _database
          .update(_database.apps)
          .write(const AppsCompanion(hidden: Value(false)));

      final categoryIds = <int>[];
      for (final category in backup.categories) {
        final inserted = await _database
            .into(_database.categories)
            .insertReturning(
              CategoriesCompanion.insert(
                name: category.name,
                sort: Value(category.sort),
                type: Value(category.type),
                rowHeight: Value(category.rowHeight),
                columnsCount: Value(category.columnsCount),
                order: category.order,
              ),
            );
        categoryIds.add(inserted.id);
      }

      for (int i = 0; i < backup.categories.length; i++) {
        final categoryId = categoryIds[i];
        final appPackageNames = backup.categories[i].apps
            .where(installedPackages.contains)
            .toList();
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

      for (final packageName in backup.hiddenApps) {
        if (installedPackages.contains(packageName)) {
          await _database.updateApp(
            packageName,
            const AppsCompanion(hidden: Value(true)),
          );
        }
      }
    });
  }
}

/// A backup JSON payload, fully parsed and validated (including enum names and the wallpaper's
/// base64) up front so `_restoreFromBackup` can restore it without any further parsing that could
/// throw partway through.
class _ParsedBackup {
  final bool use24HourTimeFormat;
  final bool appHighlightAnimationEnabled;
  final String? gradientUuid;
  final int? picsumPhotoId;
  final bool picsumGrayscale;
  final int? picsumBlur;
  final List<_ParsedCategory> categories;
  final List<String> hiddenApps;
  final List<({int keyCode, String packageName})> buttonMappings;
  final List<TvInputConfig> tvInputs;
  final Uint8List? wallpaperBytes;

  _ParsedBackup({
    required this.use24HourTimeFormat,
    required this.appHighlightAnimationEnabled,
    required this.gradientUuid,
    required this.picsumPhotoId,
    required this.picsumGrayscale,
    required this.picsumBlur,
    required this.categories,
    required this.hiddenApps,
    required this.buttonMappings,
    required this.tvInputs,
    required this.wallpaperBytes,
  });

  factory _ParsedBackup.fromJson(Map<String, dynamic> data) {
    final settingsMap = data['settings'] as Map<String, dynamic>;
    final wallpaperBytesBase64 = data['wallpaperBytesBase64'] as String?;

    return _ParsedBackup(
      use24HourTimeFormat: settingsMap['use24HourTimeFormat'] as bool,
      appHighlightAnimationEnabled:
          settingsMap['appHighlightAnimationEnabled'] as bool,
      gradientUuid: settingsMap['gradientUuid'] as String?,
      picsumPhotoId: settingsMap['picsumPhotoId'] as int?,
      picsumGrayscale: settingsMap['picsumGrayscale'] as bool,
      picsumBlur: settingsMap['picsumBlur'] as int?,
      categories: (data['categories'] as List<dynamic>)
          .map((json) => _ParsedCategory.fromJson(json as Map<String, dynamic>))
          .toList(),
      hiddenApps: (data['hiddenApps'] as List<dynamic>).cast<String>(),
      buttonMappings: (data['buttonMappings'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (json) => (
              keyCode: json['keyCode'] as int,
              packageName: json['packageName'] as String,
            ),
          )
          .toList(),
      tvInputs: ((data['tvInputs'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>()
          .map(TvInputConfig.fromJson)
          .toList(),
      wallpaperBytes: wallpaperBytesBase64 != null
          ? base64Decode(wallpaperBytesBase64)
          : null,
    );
  }
}

class _ParsedCategory {
  final String name;
  final CategorySort sort;
  final CategoryType type;
  final int rowHeight;
  final int columnsCount;
  final int order;
  final List<String> apps;

  _ParsedCategory({
    required this.name,
    required this.sort,
    required this.type,
    required this.rowHeight,
    required this.columnsCount,
    required this.order,
    required this.apps,
  });

  factory _ParsedCategory.fromJson(Map<String, dynamic> json) =>
      _ParsedCategory(
        name: json['name'] as String,
        sort: CategorySort.values.byName(json['sort'] as String),
        type: CategoryType.values.byName(json['type'] as String),
        rowHeight: json['rowHeight'] as int,
        columnsCount: json['columnsCount'] as int,
        order: json['order'] as int,
        apps: (json['apps'] as List<dynamic>).cast<String>(),
      );
}

class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => message;
}
