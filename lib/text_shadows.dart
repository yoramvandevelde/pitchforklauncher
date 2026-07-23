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

import 'package:flutter/material.dart';

/// Shared drop-shadow behind text/icons that sit directly over the wallpaper (category headers,
/// the clock, the settings icon) so they stay legible against any photo. One shared constant
/// instead of four copies so the look stays consistent and only needs one edit to tweak.
const List<Shadow> kOverlayTextShadows = [
  Shadow(color: Color(0xB3000000), offset: Offset(1, 1), blurRadius: 8),
];
