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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shown after a remote button has been captured, to pick which app it should launch. Pops with
/// the selected package name, or null if dismissed.
class PickAppForButtonDialog extends StatelessWidget {
  final String buttonLabel;

  PickAppForButtonDialog(this.buttonLabel);

  @override
  Widget build(BuildContext context) => Selector<AppsService, List<App>>(
        selector: (_, appsService) => appsService.applications,
        builder: (context, applications, _) => SimpleDialog(
          title: Text("Launch which app on $buttonLabel?"),
          contentPadding: EdgeInsets.all(16),
          children: applications
              .map(
                (application) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    autofocus: application == applications.first,
                    onTap: () => Navigator.of(context).pop(application.packageName),
                    leading: application.icon != null ? Image.memory(application.icon!, height: 32) : null,
                    title: Text(application.name),
                  ),
                ),
              )
              .toList(),
        ),
      );
}
