/*
 * FLauncher
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

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FLauncherAboutDialog extends StatelessWidget {
  final PackageInfo packageInfo;

  FLauncherAboutDialog({
    super.key,
    required this.packageInfo,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium!;
    final underlined = textStyle.copyWith(decoration: TextDecoration.underline);
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
        );
    return AboutDialog(
      applicationName: packageInfo.appName,
      applicationIcon: Image.asset("assets/logo.png", height: 72),
      children: [
        Text("${packageInfo.version} (${packageInfo.buildNumber})", style: mutedStyle),
        SizedBox(height: 8),
        Text("© 2021 Étienne Fesser\n© 2026 Yoram van de Velde", style: mutedStyle),
        SizedBox(height: 24),
        RichText(
          text: TextSpan(
            style: textStyle,
            children: [
              TextSpan(
                text: "PitchforkLauncher is an open-source alternative launcher for Android TV.\n"
                    "Source code available at ",
              ),
              TextSpan(text: "https://github.com/yoramvandevelde/pitchforklauncher", style: underlined),
              TextSpan(text: ".\n\n"),
              TextSpan(
                text: "A personal fork of FLauncher by Étienne Fesser — thanks for the solid\n"
                    "foundation. Original project at ",
              ),
              TextSpan(text: "https://gitlab.com/flauncher/flauncher", style: underlined),
              TextSpan(text: ".\n\n"),
              TextSpan(text: "Logo by Katie "),
              TextSpan(text: "@fureturoe", style: underlined),
              TextSpan(text: ", "),
              TextSpan(text: "design by "),
              TextSpan(text: "@FXCostanzo", style: underlined),
              TextSpan(text: "."),
            ],
          ),
        )
      ],
    );
  }
}
