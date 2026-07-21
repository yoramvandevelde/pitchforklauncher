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

import 'dart:typed_data';
import 'dart:ui';

import 'package:http/http.dart';

class PicsumPhoto {
  final int id;
  final Uint8List bytes;

  const PicsumPhoto({required this.id, required this.bytes});
}

class PicsumException implements Exception {
  final String message;

  PicsumException(this.message);

  @override
  String toString() => "PicsumException: $message";
}

class PicsumService {
  final Client _client;

  PicsumService({Client? client}) : _client = client ?? Client();

  /// Fetches a fresh, unfiltered random photo and captures its Picsum id so it can later be
  /// re-fetched with different filters via [photoById] instead of rolling a new random photo.
  ///
  /// picsum.photos/{w}/{h} is itself just a redirect to a specific numbered photo
  /// (fastly.picsum.photos/id/{id}/{w}/{h}.jpg) -- http.get() would auto-follow that redirect and
  /// discard it, so the redirect is followed manually here to read the id out of it first.
  Future<PicsumPhoto> randomPhoto() async {
    final size = PlatformDispatcher.instance.implicitView!.physicalSize;
    final uri = Uri.parse("https://picsum.photos/${size.width.toInt()}/${size.height.toInt()}");
    final probeRequest = Request("GET", uri)..followRedirects = false;
    final probeResponse = await Response.fromStream(await _client.send(probeRequest));
    final location = probeResponse.headers["location"];
    if (probeResponse.statusCode < 300 || probeResponse.statusCode >= 400 || location == null) {
      throw PicsumException("Expected a redirect with a Location header from $uri, got ${probeResponse.statusCode}");
    }
    final resolved = uri.resolve(location);
    final id = _idFromResolvedUri(resolved);
    final response = await _client.get(resolved);
    return PicsumPhoto(id: id, bytes: response.bodyBytes);
  }

  /// Re-fetches the same numbered photo, optionally with grayscale/blur applied. Both filters are
  /// combinable in a single request (confirmed against the live API).
  Future<Uint8List> photoById(int id, {bool grayscale = false, int? blur}) async {
    final size = PlatformDispatcher.instance.implicitView!.physicalSize;
    final base = "https://picsum.photos/id/$id/${size.width.toInt()}/${size.height.toInt()}";
    final params = <String>[if (grayscale) "grayscale", if (blur != null) "blur=$blur"];
    final uri = Uri.parse(params.isEmpty ? base : "$base?${params.join("&")}");
    final response = await _client.get(uri);
    return response.bodyBytes;
  }

  int _idFromResolvedUri(Uri uri) {
    final segments = uri.pathSegments;
    final index = segments.indexOf("id");
    if (index == -1 || index + 1 >= segments.length) {
      throw PicsumException("Could not parse a photo id from $uri");
    }
    return int.parse(segments[index + 1]);
  }
}
