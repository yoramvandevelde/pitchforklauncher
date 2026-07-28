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

/// One field a [TvInputProfile] needs from the user (e.g. the TV's IP). Used to render the
/// add/edit form in TvInputsPanelPage generically, without the UI hardcoding any one profile's
/// fields.
class TvInputParamSpec {
  final String key;
  final String label;

  const TvInputParamSpec({required this.key, required this.label});
}

/// A pluggable "how do I tell this brand of TV to switch input" implementation.
///
/// To add support for another TV brand/protocol:
/// 1. Create a class implementing [TvInputProfile] (see `samsung_tizen_profile.dart` for a
///    worked example).
/// 2. Give it a stable, never-renamed [id] -- it's persisted in [TvInputConfig.profileId], so
///    renaming it orphans any input a user already configured with the old id.
/// 3. Declare the fields you need from the user via [paramSpecs]; TvInputsPanelPage renders a
///    text field per spec automatically.
/// 4. Add an instance to `tvInputProfiles` in `tv_input_profiles.dart`.
/// No other file (storage, UI, trigger) needs to change -- they all go through this interface.
abstract class TvInputProfile {
  String get id;

  String get displayName;

  List<TvInputParamSpec> get paramSpecs;

  /// Sends whatever brand-specific command switches the TV to this input. [params] contains one
  /// entry per [paramSpecs] key, as entered by the user, plus any extra values a previous call
  /// chose to persist (see the return value below). Implementations should let failures
  /// propagate -- [TvInputService.select] is responsible for catching and logging them.
  ///
  /// Returns an updated params map to have [TvInputService] persist it back onto the stored
  /// input (merged over the existing params), or null if nothing needs saving. This exists for
  /// protocols that hand back a pairing token on first connect (see `samsung_tizen_profile.dart`)
  /// that must be resent on later calls to avoid re-prompting the user every time.
  Future<Map<String, String>?> selectInput(Map<String, String> params);
}
