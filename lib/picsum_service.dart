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

  // The underlying TCP connect timeout (~60s on Android) is far too long to make a user wait on
  // what's meant to be a quick "get a new wallpaper" action -- fail fast instead so an offline/
  // unreachable network shows up in AppLog within a few seconds rather than a minute. Overridable
  // so tests can exercise the timeout path without actually waiting on it.
  final Duration _timeout;

  PicsumService({Client? client, this._timeout = const Duration(seconds: 10)}) : _client = client ?? Client();

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
    final probeResponse = await Response.fromStream(await _timed(_client.send(probeRequest), uri));
    final location = probeResponse.headers["location"];
    if (probeResponse.statusCode < 300 || probeResponse.statusCode >= 400 || location == null) {
      throw PicsumException("Expected a redirect with a Location header from $uri, got ${probeResponse.statusCode}");
    }
    final resolved = uri.resolve(location);
    final id = _idFromResolvedUri(resolved);
    final response = await _timed(_client.get(resolved), resolved);
    return PicsumPhoto(id: id, bytes: _bodyBytesOrThrow(response, resolved));
  }

  /// Re-fetches the same numbered photo, optionally with grayscale/blur applied. Both filters are
  /// combinable in a single request (confirmed against the live API).
  Future<Uint8List> photoById(int id, {bool grayscale = false, int? blur}) async {
    final size = PlatformDispatcher.instance.implicitView!.physicalSize;
    final base = "https://picsum.photos/id/$id/${size.width.toInt()}/${size.height.toInt()}";
    final params = <String>[if (grayscale) "grayscale", if (blur != null) "blur=$blur"];
    final uri = Uri.parse(params.isEmpty ? base : "$base?${params.join("&")}");
    final response = await _timed(_client.get(uri), uri);
    return _bodyBytesOrThrow(response, uri);
  }

  Future<T> _timed<T>(Future<T> future, Uri uri) => future.timeout(
        _timeout,
        onTimeout: () => throw PicsumException("Timed out after ${_timeout.inSeconds}s waiting for a response from $uri"),
      );

  Uint8List _bodyBytesOrThrow(Response response, Uri uri) {
    if (response.statusCode != 200) {
      throw PicsumException("Expected a 200 response from $uri, got ${response.statusCode}");
    }
    return response.bodyBytes;
  }

  int _idFromResolvedUri(Uri uri) {
    final segments = uri.pathSegments;
    final index = segments.indexOf("id");
    final id = index == -1 || index + 1 >= segments.length ? null : int.tryParse(segments[index + 1]);
    if (id == null) {
      throw PicsumException("Could not parse a photo id from $uri");
    }
    return id;
  }
}
