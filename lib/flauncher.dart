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

import 'dart:typed_data';

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/text_shadows.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/time_widget.dart';
import 'package:flauncher/widgets/tv_input_trigger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatelessWidget {
  // How far down the category list's resting (unscrolled) position sits -- the original, pre-
  // transparency gap (16 padding + the app bar's own default height). Hardcoded rather than
  // derived from the app bar below on purpose: extendBodyBehindAppBar means the app bar floats
  // over the content instead of reserving space for it, so nothing here actually depends on the
  // app bar's own height -- shrinking that bar was only ever about reclaiming space for content,
  // which transparency already solved, so the bar itself is back to its original size/alignment.
  static const double _categoriesTopGap = 16 + kToolbarHeight;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    policy: RowByRowTraversalPolicy(),
    child: TvInputTrigger(
      child: Stack(
        children: [
          Consumer<WallpaperService>(
            builder: (_, wallpaper, _) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              // A plain linear cross-fade has both layers partially transparent around the
              // midpoint, letting the dark canvas beneath bleed through as a brightness dip.
              // Confining each curve to the first half of its own [0,1] range means the
              // incoming photo reaches full opacity by the midpoint and the outgoing one only
              // starts fading (invisibly, since it's now hidden under an opaque top layer)
              // after that -- at every instant at least one layer is fully opaque, so the
              // background never shows through.
              switchInCurve: const Interval(0.0, 0.5, curve: Curves.easeIn),
              switchOutCurve: const Interval(0.0, 0.5, curve: Curves.easeOut),
              child: KeyedSubtree(
                key: ValueKey(wallpaper.wallpaperVersion),
                child: _wallpaper(
                  context,
                  wallpaper.wallpaperBytes,
                  wallpaper.gradient.gradient,
                ),
              ),
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: _appBar(context),
            body: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Consumer<AppsService>(
                builder: (context, appsService, _) =>
                    _AppsBody(appsService: appsService),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _categories(List<CategoryWithApps> categoriesWithApps) =>
      Column(
        children: categoriesWithApps.map((categoryWithApps) {
          switch (categoryWithApps.category.type) {
            case CategoryType.row:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CategoryRow(
                  key: Key(categoryWithApps.category.id.toString()),
                  category: categoryWithApps.category,
                  applications: categoryWithApps.applications,
                ),
              );
            case CategoryType.grid:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AppsGrid(
                  key: Key(categoryWithApps.category.id.toString()),
                  category: categoryWithApps.category,
                  applications: categoryWithApps.applications,
                ),
              );
          }
        }).toList(),
      );

  AppBar _appBar(BuildContext context) => AppBar(
    actions: [
      Align(
        alignment: Alignment.center,
        child: IconButton(
          padding: EdgeInsets.all(2),
          constraints: BoxConstraints(),
          splashRadius: 20,
          icon: Icon(Icons.settings_outlined, shadows: kOverlayTextShadows),
          onPressed: () =>
              showDialog(context: context, builder: (_) => SettingsPanel()),
        ),
      ),
      Padding(
        padding: EdgeInsets.only(left: 16, right: 32),
        child: Align(alignment: Alignment.center, child: TimeWidget()),
      ),
    ],
  );

  Widget _wallpaper(
    BuildContext context,
    Uint8List? wallpaperImage,
    Gradient gradient,
  ) {
    if (wallpaperImage == null) {
      return Container(
        key: Key("background"),
        decoration: BoxDecoration(gradient: gradient),
      );
    }
    final view = View.of(context);
    final logicalSize = view.physicalSize / view.devicePixelRatio;
    return Image.memory(
      wallpaperImage,
      key: Key("background"),
      fit: BoxFit.cover,
      height: logicalSize.height,
      width: logicalSize.width,
    );
  }
}

/// Bridges [AppsService.initialized] to the screen: while loading, an empty slot sits behind the
/// wallpaper (no spinner -- a launch is normally fast enough that one would only ever flash
/// briefly, and a slow one, e.g. a fresh install seeding default categories, is rare enough not to
/// design around); once ready, the grid cross-fades in rather than popping in, mirroring the
/// wallpaper switcher above.
class _AppsBody extends StatelessWidget {
  final AppsService appsService;

  const _AppsBody({required this.appsService});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 1000),
    // Same reasoning as the wallpaper switcher above: without confining each curve to the first
    // half, the loading slot and the grid would both be partially transparent around the
    // midpoint, letting the plain wallpaper show through as a brief dip instead of a clean
    // handoff.
    switchInCurve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    switchOutCurve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    // The default layoutBuilder centers non-positioned children in a Stack. The loading slot (no
    // intrinsic height) and the grid (fills the viewport) then get centered in a box sized to fit
    // both, which shifts the grid down from its resting top-anchored position for as long as the
    // outgoing loading slot is still a transition sibling -- top-aligning both avoids that.
    layoutBuilder: (currentChild, previousChildren) => Stack(
      alignment: Alignment.topCenter,
      children: [...previousChildren, ?currentChild],
    ),
    child: appsService.initialized
        ? _content(context)
        : const SizedBox.shrink(key: ValueKey("loading")),
  );

  Widget _content(BuildContext context) => SingleChildScrollView(
    // The top gap lives inside the scrollable content (rather than as padding around the whole
    // SingleChildScrollView) so the viewport itself spans the full screen -- scrolling can then
    // carry categories all the way up behind the transparent app bar instead of hard-clipping
    // them at a fixed line. At rest (scroll offset 0) this spacer keeps the first category at the
    // same position as before.
    key: const ValueKey("content"),
    child: Column(
      children: [
        SizedBox(height: FLauncher._categoriesTopGap),
        FLauncher._categories(appsService.categoriesWithApps),
      ],
    ),
  );
}
