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

import 'package:flauncher/actions.dart';
import 'package:flauncher/providers/tv_input_service.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/tv_inputs_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The "hold Up on the homescreen" slide-in bar listing configured [TvInputConfig]s. Mirrors
/// WallpaperControlBar's route/animation shape (see wallpaper_control_bar.dart) so the two bars
/// feel like the same UI language. When nothing is configured yet, shows a shortcut into
/// TvInputsPanelPage instead of an empty row, so the gesture doubles as a discovery path.
class TvInputBar extends StatelessWidget {
  const TvInputBar({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: UnconstrainedBox(
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
            child: Actions(
              actions: {BackIntent: BackAction(context)},
              child: const TvInputBar(),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tvInputService = context.watch<TvInputService>();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: tvInputService.inputs.isEmpty
            ? _emptyState(context)
            : _inputs(context, tvInputService),
      ),
    );
  }

  Widget _emptyState(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        "No TV inputs configured yet",
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      SizedBox(width: 24),
      TextButton(
        autofocus: true,
        onPressed: () => showDialog(
          context: context,
          builder: (_) =>
              SettingsPanel(initialRoute: TvInputsPanelPage.routeName),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_outlined),
            Container(width: 8),
            Text("Set up", style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );

  Widget _inputs(BuildContext context, TvInputService tvInputService) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (index, input) in tvInputService.inputs.indexed) ...[
        if (index > 0) SizedBox(width: 32),
        TextButton(
          autofocus: index == 0,
          onPressed: () {
            tvInputService.select(input);
            Navigator.of(context).pop();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_input_hdmi),
              Container(width: 8),
              Text(input.label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ],
  );
}
