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

import 'package:flauncher/picsum_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

void main() {
  group("randomPhoto", () {
    test("follows the redirect, captures the photo id and returns the bytes", () async {
      final client = MockClient((request) async {
        if (request.url.host == "picsum.photos") {
          return Response(
            "",
            302,
            headers: {"location": "https://fastly.picsum.photos/id/568/300/200.jpg?hmac=abc"},
          );
        }
        return Response.bytes(Uint8List.fromList([0x01, 0x02]), 200);
      });
      final picsumService = PicsumService(client: client);

      final photo = await picsumService.randomPhoto();

      expect(photo.id, 568);
      expect(photo.bytes, [0x01, 0x02]);
    });

    test("throws when the response isn't a redirect", () async {
      final client = MockClient((request) async => Response("", 200));
      final picsumService = PicsumService(client: client);

      expect(() => picsumService.randomPhoto(), throwsA(isA<PicsumException>()));
    });

    test("throws when the redirect has no Location header", () async {
      final client = MockClient((request) async => Response("", 302));
      final picsumService = PicsumService(client: client);

      expect(() => picsumService.randomPhoto(), throwsA(isA<PicsumException>()));
    });

    test("throws when the resolved photo request isn't a 200", () async {
      final client = MockClient((request) async {
        if (request.url.host == "picsum.photos") {
          return Response(
            "",
            302,
            headers: {"location": "https://fastly.picsum.photos/id/568/300/200.jpg?hmac=abc"},
          );
        }
        return Response("", 500);
      });
      final picsumService = PicsumService(client: client);

      expect(() => picsumService.randomPhoto(), throwsA(isA<PicsumException>()));
    });
  });

  // Width/height come from PlatformDispatcher.instance.implicitView, which isn't controllable
  // from these plain unit tests (it's a different object than the test-bound dispatcher outside
  // of an active testWidgets pump cycle) -- these assertions deliberately only pin down what
  // actually matters here: the /id/{id}/ path and the exact query-string filter construction.
  group("photoById", () {
    test("fetches without query params when no filters are requested", () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return Response.bytes(Uint8List.fromList([0x03]), 200);
      });
      final picsumService = PicsumService(client: client);

      final bytes = await picsumService.photoById(568);

      expect(capturedUri!.pathSegments.take(2), ["id", "568"]);
      expect(capturedUri!.query, "");
      expect(bytes, [0x03]);
    });

    test("builds a bare grayscale flag combined with blur", () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return Response.bytes(Uint8List.fromList([0x04]), 200);
      });
      final picsumService = PicsumService(client: client);

      await picsumService.photoById(568, grayscale: true, blur: 3);

      expect(capturedUri!.pathSegments.take(2), ["id", "568"]);
      expect(capturedUri!.query, "grayscale&blur=3");
    });

    test("grayscale only", () async {
      Uri? capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return Response.bytes(Uint8List.fromList([0x05]), 200);
      });
      final picsumService = PicsumService(client: client);

      await picsumService.photoById(568, grayscale: true);

      expect(capturedUri!.pathSegments.take(2), ["id", "568"]);
      expect(capturedUri!.query, "grayscale");
    });

    test("throws when the response isn't a 200", () async {
      final client = MockClient((request) async => Response("", 404));
      final picsumService = PicsumService(client: client);

      expect(() => picsumService.photoById(568), throwsA(isA<PicsumException>()));
    });
  });
}
