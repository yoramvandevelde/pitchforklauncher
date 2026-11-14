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

import 'package:flauncher/widgets/color_helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test("Should compute 2 next border color", () {
    // given
    double tick1 = 0.3;
    double tick2 = 0.5;
    Color defaultColor = Colors.red;

    // when
    var color1 = computeBorderColor(tick1, defaultColor);
    var color2 = computeBorderColor(tick2, defaultColor);

    // then
    expect(color1, isNot(isSameColorAs(color2)));
    expect(color2, isNot(isSameColorAs(defaultColor)));
    expect(color1, isNot(isSameColorAs(defaultColor)));
  });

  test("Should return default value", () {
    // given
    double tick = 1;
    Color defaultColor = Colors.red;

    // when
    var color = computeBorderColor(tick, defaultColor);

    // then
    expect(color, isSameColorAs(defaultColor));
  });

  test("Should accept value between 0 and 1", () {
    // given
    double badTick1 = 1.1;
    double badTick2 = -0.1;
    Color defaultColor = Colors.red;

    // then
    expect(
      () => computeBorderColor(badTick1, defaultColor),
      throwsAssertionError,
    );
    expect(
      () => computeBorderColor(badTick2, defaultColor),
      throwsAssertionError,
    );
  });
}
