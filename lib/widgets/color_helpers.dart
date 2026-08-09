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

import 'package:flutter/material.dart';

/// Compute a color for a border (grey based), based on the provided value.
/// The value must be between 0 and 1, otherwise an assertion error is raised.
/// The provided defaultValue is the color returned in case
/// the function cannot find a grey color.
Color computeBorderColor(double value, Color defaultValue) {
  assert(value >= 0 && value <= 1);
  // we are converting a number with a value of [0, 1] to a multiple of 100
  int val = (value * 10).round() * 100;
  Color? color = val == 0 ? Colors.white : Colors.grey[val];
  return color ?? defaultValue;
}
