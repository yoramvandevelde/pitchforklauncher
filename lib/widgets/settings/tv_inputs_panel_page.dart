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

import 'package:flauncher/providers/tv_input/tv_input_profiles.dart';
import 'package:flauncher/providers/tv_input_service.dart';
import 'package:flauncher/widgets/settings/add_tv_input_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TvInputsPanelPage extends StatelessWidget {
  static const String routeName = "tv_inputs_panel";

  @override
  Widget build(BuildContext context) => Consumer<TvInputService>(
    builder: (context, tvInputService, _) => Column(
      children: [
        Text("TV Inputs", style: Theme.of(context).textTheme.titleLarge),
        Divider(),
        Text(
          "Hold Up for 2 seconds on the homescreen to bring up a bar that switches the TV to "
          "one of these inputs.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final input in tvInputService.inputs)
                  _tile(context, tvInputService, input),
              ],
            ),
          ),
        ),
        TextButton.icon(
          icon: Icon(Icons.add),
          label: Text("Add TV Input"),
          onPressed: () async {
            final newInput = await showDialog<NewTvInput>(
              context: context,
              builder: (_) => AddTvInputDialog(),
            );
            if (newInput != null) {
              await tvInputService.addInput(
                label: newInput.label,
                profileId: newInput.profileId,
                params: newInput.params,
              );
            }
          },
        ),
      ],
    ),
  );

  Widget _tile(
    BuildContext context,
    TvInputService tvInputService,
    TvInputConfig input,
  ) => Card(
    margin: EdgeInsets.only(bottom: 8),
    child: ListTile(
      dense: true,
      title: Text(input.label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(
        tvInputProfiles[input.profileId]?.displayName ?? input.profileId,
      ),
      trailing: IconButton(
        constraints: BoxConstraints(),
        splashRadius: 20,
        icon: Icon(Icons.delete_outline),
        onPressed: () => tvInputService.removeInput(input.id),
      ),
    ),
  );
}
