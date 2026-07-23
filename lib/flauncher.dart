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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FLauncher extends StatelessWidget {
  // Shared with _appBar's toolbarHeight: extendBodyBehindAppBar lets the category list scroll up
  // behind the transparent app bar instead of being hard-clipped below it, but the body's own
  // layout box now starts at y=0 -- without this compensating top padding, the resting (unscrolled)
  // position would sit this much higher than before.
  static const double _appBarHeight = 40;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        policy: RowByRowTraversalPolicy(),
        child: Stack(
          children: [
            Consumer<WallpaperService>(
              builder: (_, wallpaper, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
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
                  child: _wallpaper(context, wallpaper.wallpaperBytes, wallpaper.gradient.gradient),
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
                  builder: (context, appsService, _) => appsService.initialized
                      ? SingleChildScrollView(
                          // The top gap lives inside the scrollable content (rather than as
                          // padding around the whole SingleChildScrollView) so the viewport itself
                          // spans the full screen -- scrolling can then carry categories all the
                          // way up behind the transparent app bar instead of hard-clipping them at
                          // a fixed line. At rest (scroll offset 0) this spacer keeps the first
                          // category at the same position as before.
                          child: Column(
                            children: [
                              SizedBox(height: 16 + _appBarHeight),
                              _categories(appsService.categoriesWithApps),
                            ],
                          ),
                        )
                      : _emptyState(context),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _categories(List<CategoryWithApps> categoriesWithApps) => Column(
        children: categoriesWithApps.map((categoryWithApps) {
          switch (categoryWithApps.category.type) {
            case CategoryType.row:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CategoryRow(
                    key: Key(categoryWithApps.category.id.toString()),
                    category: categoryWithApps.category,
                    applications: categoryWithApps.applications),
              );
            case CategoryType.grid:
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: AppsGrid(
                    key: Key(categoryWithApps.category.id.toString()),
                    category: categoryWithApps.category,
                    applications: categoryWithApps.applications),
              );
          }
        }).toList(),
      );

  AppBar _appBar(BuildContext context) => AppBar(
        toolbarHeight: _appBarHeight,
        actions: [
          Align(
            alignment: Alignment.bottomCenter,
            child: IconButton(
              padding: EdgeInsets.all(2),
              constraints: BoxConstraints(),
              splashRadius: 20,
              icon: Icon(
                Icons.settings_outlined,
                shadows: kOverlayTextShadows,
              ),
              onPressed: () => showDialog(context: context, builder: (_) => SettingsPanel()),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: 16, right: 32),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TimeWidget(),
            ),
          ),
        ],
      );

  Widget _wallpaper(BuildContext context, Uint8List? wallpaperImage, Gradient gradient) {
    if (wallpaperImage == null) {
      return Container(key: Key("background"), decoration: BoxDecoration(gradient: gradient));
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

  Widget _emptyState(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Loading...", style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      );
}
