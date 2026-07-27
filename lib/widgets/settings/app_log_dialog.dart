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

import 'package:flauncher/app_log.dart';
import 'package:flutter/material.dart';

class AppLogDialog extends StatelessWidget {
  const AppLogDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("Logs"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListenableBuilder(
            listenable: AppLog.instance,
            builder: (context, _) {
              final entries = AppLog.instance.entries;
              if (entries.isEmpty) {
                return Text("No errors logged since the app was last started.");
              }
              return SingleChildScrollView(
                child: SelectableText(
                  entries.join("\n"),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: "monospace"),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Close"),
          ),
        ],
      );
}
