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

import 'package:flauncher/actions.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _picsumBlurAmount = 4;

class WallpaperControlBar extends StatefulWidget {
  const WallpaperControlBar({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: UnconstrainedBox(
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                    .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                child: Actions(
                  actions: {BackIntent: BackAction(context)},
                  child: const WallpaperControlBar(),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  State<WallpaperControlBar> createState() => _WallpaperControlBarState();
}

class _WallpaperControlBarState extends State<WallpaperControlBar> {
  bool _grayscale = false;
  bool _blur = false;

  Future<void> _onRandom() async {
    setState(() {
      _grayscale = false;
      _blur = false;
    });
    await context.read<WallpaperService>().randomFromPicsum();
  }

  Future<void> _onGrayscaleChanged(bool value) async {
    setState(() => _grayscale = value);
    await context
        .read<WallpaperService>()
        .reapplyPicsumFilters(grayscale: _grayscale, blur: _blur ? _picsumBlurAmount : null);
  }

  Future<void> _onBlurChanged(bool value) async {
    setState(() => _blur = value);
    await context
        .read<WallpaperService>()
        .reapplyPicsumFilters(grayscale: _grayscale, blur: _blur ? _picsumBlurAmount : null);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = context.watch<WallpaperService>().hasCurrentPicsumPhoto;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              autofocus: true,
              onPressed: _onRandom,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shuffle),
                  Container(width: 8),
                  Text("Random", style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            SizedBox(width: 32),
            _FilterToggle(
              icon: Icons.filter_b_and_w,
              label: "Black & White",
              value: _grayscale,
              onChanged: hasPhoto ? _onGrayscaleChanged : null,
            ),
            SizedBox(width: 32),
            _FilterToggle(
              icon: Icons.blur_on,
              label: "Blur",
              value: _blur,
              onChanged: hasPhoto ? _onBlurChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _FilterToggle({required this.icon, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final color = onChanged == null ? Theme.of(context).disabledColor : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        Container(width: 8),
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        Container(width: 8),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
