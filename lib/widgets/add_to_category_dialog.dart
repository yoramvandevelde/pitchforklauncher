/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

class AddToCategoryDialog extends StatelessWidget {
  final App application;

  /// When set, selecting a category also removes [application] from this category instead of
  /// just adding it to the new one -- i.e. this dialog doubles as "Move to..." (used from the
  /// home screen's app context menu) as well as plain "Add to..." (used from Settings >
  /// Applications). The category list is unaffected either way: it's already filtered down to
  /// categories that don't contain the app yet, so [moveFrom] itself never appears as an option.
  final Category? moveFrom;

  AddToCategoryDialog(this.application, {this.moveFrom});

  @override
  Widget build(BuildContext context) => Selector<AppsService, List<Category>>(
        selector: (_, appsService) => appsService.categoriesWithApps
            .where((element) => !element.applications.any((app) => app.packageName == application.packageName))
            .map((categoryWithApps) => categoryWithApps.category)
            .toList(),
        builder: (context, categories, _) => SimpleDialog(
          title: Text(moveFrom != null ? "Move to..." : "Add to..."),
          contentPadding: EdgeInsets.all(16),
          children: categories
              .map(
                (category) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () async {
                      final appsService = context.read<AppsService>();
                      if (moveFrom != null) {
                        await appsService.moveToCategory(application, moveFrom!, category);
                      } else {
                        await appsService.addToCategory(application, category);
                      }
                      Navigator.of(context).pop();
                    },
                    title: Text(category.name),
                  ),
                ),
              )
              .toList(),
        ),
      );
}
