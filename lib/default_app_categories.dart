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

/// Package name -> category name, used by [AppsService]'s first-run seeding
/// (`_initDefaultCategories`) to sort well-known apps into topical categories instead of the
/// generic sideloaded/non-sideloaded split. Anything not listed here falls back to that split.
///
/// Both the grouping (which category an app lands in) and the display order (which category
/// shows first, and which app shows first within a category) directly follow this file's own
/// order -- reorder/add/remove entries directly to change either; there's deliberately no config
/// file or remote source. Package names were verified against the Play Store one by one (LLM
/// suggestions for these are frequently wrong/hallucinated -- roughly 40% of an initial batch
/// didn't exist), so don't add an entry here without checking it actually resolves to the
/// intended app first.
const Map<String, String> defaultAppCategories = {
  // Streaming
  "com.netflix.ninja": "Streaming",
  "com.netflix.mediaclient": "Streaming",
  "com.google.android.youtube.tv": "Streaming",
  "com.google.android.youtube": "Streaming",
  "com.disney.disneyplus": "Streaming",
  "com.amazon.avod.thirdpartyclient": "Streaming",
  "com.amazon.amazonvideo.livingroom": "Streaming",
  "com.wbd.hbomax": "Streaming",
  "com.apple.atve.androidtv.appletv": "Streaming",
  "com.skyshowtime.skyshowtime.google": "Streaming",
  "com.tubitv": "Streaming",
  "tv.pluto.android": "Streaming",
  "be.vrt.vrtnu": "Streaming",
  "nl.uitzendinggemist": "Streaming",
  "com.viaplay.android": "Streaming",
  "com.espn.score_center": "Streaming",
  "nl.rtl.videoland.v2": "Streaming",
  "tv.twitch.android.app": "Streaming",
  "com.spotify.tv.android": "Streaming",

  // Media
  "org.xbmc.kodi": "Media",
  "org.videolan.vlc": "Media",
  "com.plexapp.android": "Media",
  "org.jellyfin.androidtv": "Media",
  "com.stremio.one": "Media",
  "com.smarttube.downloader": "Media",

  // System
  "com.google.android.apps.education.cast2class": "System",
  "com.android.vending": "System",
  "com.android.tv.settings": "System",
  "com.esaba.downloader": "System",
  "com.yablio.sendfilestotv": "System",
  "com.lonelycatgames.Xplore": "System",
  "com.nordvpn.android": "System",
  "com.surfshark.vpnclient.android": "System",
  "flar2.homebutton": "System",
};

/// Per-category display overrides applied by [AppsService]'s first-run seeding, keyed by category
/// name -- both the topical names above and the "TV Applications"/"System" fallback names. A
/// category with no entry here (e.g. "Non-TV Applications") is left at the app's normal defaults
/// (grid, row height 110, 6 columns; see `Categories` in database.dart). Edit directly to change
/// how any seeded category looks, same as [defaultAppCategories] -- no config file or remote
/// source. Every field is stated explicitly rather than relying on "leave it at the default" for
/// categories that need grid: the actual database column default is `CategoryType.row` (index 0),
/// not grid, so an omitted [DefaultCategorySettings.type] is only safe for categories that are
/// genuinely meant to render as a row.
const Map<String, DefaultCategorySettings> defaultCategorySettings = {
  "TV Applications": DefaultCategorySettings(type: CategoryType.row, rowHeight: 80),
  "Streaming": DefaultCategorySettings(type: CategoryType.grid, columnsCount: 5),
  "Media": DefaultCategorySettings(type: CategoryType.grid),
  "System": DefaultCategorySettings(type: CategoryType.row, rowHeight: 80),
};

class DefaultCategorySettings {
  final CategoryType? type;
  final int? rowHeight;
  final int? columnsCount;

  const DefaultCategorySettings({this.type, this.rowHeight, this.columnsCount});
}
