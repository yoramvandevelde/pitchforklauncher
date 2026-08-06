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
import 'package:flauncher/providers/tv_input/tv_input_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("registers every shipped profile keyed by its own id", () {
    expect(tvInputProfiles.keys, containsAll(["samsung_tizen"]));
    for (final entry in tvInputProfiles.entries) {
      expect(entry.value.id, entry.key, reason: "profile must be keyed by its own id");
    }
  });

  test("ships the Samsung Tizen profile", () {
    expect(tvInputProfiles["samsung_tizen"], isA<SamsungTizenProfile>());
  });
}
