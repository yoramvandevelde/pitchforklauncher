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

import 'package:flauncher/providers/tv_input/samsung_tizen_profile.dart';
import 'package:flauncher/providers/tv_input/tv_input_profile.dart';

/// The set of TV control profiles PitchforkLauncher ships with, keyed by [TvInputProfile.id].
/// See the doc comment on [TvInputProfile] for how to add a new one -- this map is the only place
/// a new profile needs to be registered.
final Map<String, TvInputProfile> tvInputProfiles = {
  for (final profile in [SamsungTizenProfile()]) profile.id: profile,
};
