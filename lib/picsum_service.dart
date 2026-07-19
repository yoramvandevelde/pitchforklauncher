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
import 'dart:ui';

import 'package:http/http.dart';

class PicsumService {
  Future<Uint8List> randomPhoto({int? blur}) async {
    final size = window.physicalSize;
    final uri = Uri.parse("https://picsum.photos/${size.width.toInt()}/${size.height.toInt()}")
        .replace(queryParameters: blur != null ? {"blur": "$blur"} : null);
    final response = await get(uri);
    return response.bodyBytes;
  }
}