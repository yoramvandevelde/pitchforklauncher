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

/// Package name -> category name, used by [AppsService]'s first-run seeding
/// (`_initDefaultCategories`) to sort well-known apps into topical categories instead of the
/// generic sideloaded/non-sideloaded split. Anything not listed here falls back to that split.
///
/// Entries are grouped by category, and that grouping determines display order (the category
/// whose apps appear first in this map is created first) -- see `_initDefaultCategories`.
/// Reorder/add/remove entries directly; there's deliberately no config file or remote source.
const Map<String, String> defaultAppCategories = {
  // Apps
  "com.google.android.youtube.tv": "Apps",
  "com.google.android.youtube": "Apps",
  "com.wbd.hbomax": "Apps",
  "com.netflix.ninja": "Apps",
  "com.netflix.mediaclient": "Apps",
  "com.amazon.amazonvideo.livingroom": "Apps",
  "com.disney.disneyplus": "Apps",
  "com.plexapp.android": "Apps",
  "com.spotify.tv.android": "Apps",
  "org.videolan.vlc": "Apps",
  "org.xbmc.kodi": "Apps",
  "nl.uitzendinggemist": "Apps",
  "nl.rtl.videoland.v2": "Apps",

  // System
  "com.android.vending": "System",
  "com.android.tv.settings": "System",
  "com.google.android.apps.education.cast2class": "System",
};
