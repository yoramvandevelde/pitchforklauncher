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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flauncher/widgets/pick_app_for_button_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ButtonMappingPanelPage extends StatelessWidget {
  static const String routeName = "button_mapping_panel";

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text("Remote buttons", style: Theme.of(context).textTheme.titleLarge),
          Divider(),
          Text(
            "Home is always PitchforkLauncher's own button. Map any other remote button to launch an app.",
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          Selector<ButtonMappingService, List<ButtonMapping>>(
            selector: (_, service) => service.mappings,
            builder: (context, mappings, __) => Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: mappings.map((mapping) => _mapping(context, mapping)).toList(),
                ),
              ),
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.add),
            label: Text("Add mapping"),
            onPressed: () => _addMapping(context),
          ),
        ],
      );

  Widget _mapping(BuildContext context, ButtonMapping mapping) {
    final applications = context.read<AppsService>().applications;
    App? app;
    for (final application in applications) {
      if (application.packageName == mapping.packageName) {
        app = application;
        break;
      }
    }
    return Padding(
      key: Key(mapping.keyCode.toString()),
      padding: EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: EnsureVisible(
          alignment: 0.5,
          child: ListTile(
            dense: true,
            leading: app?.icon != null ? Image.memory(app!.icon!, height: 32) : Icon(Icons.apps),
            title: Text(app?.name ?? mapping.packageName, style: Theme.of(context).textTheme.bodyMedium),
            subtitle: Text(mapping.label, style: Theme.of(context).textTheme.bodySmall),
            trailing: IconButton(
              constraints: BoxConstraints(),
              splashRadius: 20,
              icon: Icon(Icons.delete_outline),
              onPressed: () => context.read<ButtonMappingService>().removeMapping(mapping.keyCode),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addMapping(BuildContext context) async {
    final buttonMappingService = context.read<ButtonMappingService>();
    // showDialog() below targets the root navigator by default (useRootNavigator: true), which
    // is *not* the same Navigator.of(context) would find here — ButtonMappingPanelPage lives
    // inside SettingsPanel's own nested Navigator. Match it explicitly, otherwise pop() closes
    // the wrong thing (silently navigating the Settings panel instead of the dialog).
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Map<dynamic, dynamic>? captured;
    final subscription = buttonMappingService.captureNextButton().listen((event) {
      captured = event;
      rootNavigator.pop();
    });

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Press a button"),
        content: Text("Press the remote button you want to map. It won't do anything else while this is open."),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => rootNavigator.pop(),
            child: Text("Cancel"),
          ),
        ],
      ),
    );
    subscription.cancel();
    if (captured == null) {
      return;
    }

    final keyCode = captured!["keyCode"] as int;
    final label = captured!["label"] as String;
    final selectedPackage = await showDialog<String>(
      context: context,
      builder: (_) => PickAppForButtonDialog(label),
    );
    if (selectedPackage != null) {
      await buttonMappingService.setMapping(keyCode, selectedPackage);
    }
  }
}
