/*
 * PitchforkLauncher
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
import 'package:flauncher/widgets/settings/tv_inputs_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PitchforkSettingsPanelPage extends StatelessWidget {
  static const String routeName = "pitchfork_settings_panel";

  @override
  Widget build(BuildContext context) => Consumer<SettingsService>(
    builder: (context, settingsService, _) => SingleChildScrollView(
      child: Column(
        children: [
          Text(
            "Pitchfork Settings",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Divider(),
          TextButton(
            child: Row(
              children: [
                Icon(Icons.settings_input_hdmi),
                Container(width: 8),
                Text(
                  "TV Inputs",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            onPressed: () =>
                Navigator.of(context).pushNamed(TvInputsPanelPage.routeName),
          ),
          TextButton(
            child: Row(
              children: [
                Icon(Icons.home_outlined),
                Container(width: 8),
                Text(
                  "Set as Home button target",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            onPressed: () =>
                context.read<AppsService>().openAccessibilitySettings(),
          ),
          TextButton(
            child: Row(
              children: [
                Icon(Icons.gamepad_outlined),
                Container(width: 8),
                Text(
                  "Remote buttons",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            onPressed: () => Navigator.of(
              context,
            ).pushNamed(ButtonMappingPanelPage.routeName),
          ),
          Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
            value: settingsService.use24HourTimeFormat,
            onChanged: (value) => settingsService.setUse24HourTimeFormat(value),
            title: Text("Use 24-hour time format"),
            dense: true,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
            value: settingsService.appHighlightAnimationEnabled,
            onChanged: (value) =>
                settingsService.setAppHighlightAnimationEnabled(value),
            title: Text("App card highlight animation"),
            dense: true,
          ),
          Divider(),
          TextButton(
            child: Row(
              children: [
                Icon(Icons.backup_outlined),
                Container(width: 8),
                Text("Backup", style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            onPressed: () => _backup(context),
          ),
          TextButton(
            child: Row(
              children: [
                Icon(Icons.restore_outlined),
                Container(width: 8),
                Text("Restore", style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            onPressed: () => _restore(context),
          ),
        ],
      ),
    ),
  );

  Future<void> _backup(BuildContext context) async {
    final backupService = context.read<SettingsBackupService>();
    if (!await _ensureStorageAvailable(context, backupService) ||
        !context.mounted) {
      return;
    }
    final confirmed = await _showBackupConfirmationDialog(context);
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await backupService.exportSettings();
      if (context.mounted) {
        await _showResultDialog(
          context,
          "Backed up",
          "Settings saved to Downloads/${SettingsBackupService.backupFileName}.",
        );
      }
    } on BackupException catch (e) {
      if (context.mounted) {
        await _showResultDialog(context, "Backup failed", e.toString());
      }
    }
  }

  Future<bool?> _showBackupConfirmationDialog(BuildContext context) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Back up settings?"),
          content: Text(
            "This will overwrite the previous backup in "
            "Downloads/${SettingsBackupService.backupFileName}.",
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text("Back up"),
            ),
          ],
        ),
      );

  Future<void> _restore(BuildContext context) async {
    final backupService = context.read<SettingsBackupService>();
    if (!await _ensureStorageAvailable(context, backupService) ||
        !context.mounted) {
      return;
    }
    final confirmed = await _showRestoreConfirmationDialog(context);
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await backupService.importSettings();
      if (context.mounted) {
        await _showResultDialog(
          context,
          "Restored",
          "Your settings have been restored from the backup.",
        );
      }
    } on BackupException catch (e) {
      if (context.mounted) {
        await _showResultDialog(context, "Restore failed", e.toString());
      }
    }
  }

  /// Checks storage access before Backup/Restore proceeds, prompting appropriately if it isn't
  /// there yet, and returns whether it's safe to continue. Two different reasons
  /// [SettingsBackupService.isStorageAvailable] can be false need two different responses: the
  /// permission just isn't granted yet (fixable -- offer to open Settings) versus the OS version
  /// is too old for the underlying API to exist at all (not fixable -- offering "Open Settings"
  /// there would either fail to resolve or lead to a screen that can't help).
  Future<bool> _ensureStorageAvailable(
    BuildContext context,
    SettingsBackupService backupService,
  ) async {
    if (await backupService.isStorageAvailable()) {
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    if (!await backupService.isStorageSupported()) {
      if (context.mounted) {
        await _showResultDialog(
          context,
          "Not supported",
          "Backup/Restore needs Android 11 or newer.",
        );
      }
      return false;
    }
    if (context.mounted) {
      await _showGrantAccessDialog(context, backupService);
    }
    return false;
  }

  /// [context] here is the page's own, long-lived context (passed down from [_backup]/[_restore]
  /// via [_ensureStorageAvailable]) -- deliberately not shadowed by the dialog builder's own
  /// context below. The "Open Settings" button pops the dialog and then awaits a platform call
  /// before deciding whether to show a follow-up dialog; by that point the dialog route's own
  /// context is unmounted, so that follow-up needs the page's context to still work, not the
  /// (by-then-gone) dialog's.
  Future<void> _showGrantAccessDialog(
    BuildContext context,
    SettingsBackupService backupService,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Needs "All files access"'),
      content: Text(
        "Backup/Restore read and write "
        "Downloads/${SettingsBackupService.backupFileName}, which needs the "
        '"All files access" permission. Grant it in Settings, then try again.',
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text("Cancel"),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            final opened = await backupService.openStoragePermissionSettings();
            if (!opened && context.mounted) {
              await _showResultDialog(
                context,
                "Couldn't open Settings",
                "Grant \"All files access\" manually in Android Settings > Apps > "
                    "PitchforkLauncher, then try again.",
              );
            }
          },
          child: Text("Open Settings"),
        ),
      ],
    ),
  );

  Future<bool?> _showRestoreConfirmationDialog(
    BuildContext context,
  ) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Restore settings?"),
      content: Text(
        "This will replace all current settings, categories, app assignments, "
        "remote button mappings and wallpaper with the backup from "
        "Downloads/${SettingsBackupService.backupFileName}.",
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text("Cancel"),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text("Restore"),
        ),
      ],
    ),
  );

  Future<void> _showResultDialog(
    BuildContext context,
    String title,
    String message,
  ) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text("OK"),
        ),
      ],
    ),
  );
}
