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

import 'dart:convert';

import 'package:flauncher/providers/tv_input/samsung_tizen_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

/// Builds a [SamsungTizenProfile] whose socket connector always hands back [socket], regardless
/// of the URL/client passed in, and records the URL each call was made with.
SamsungTizenProfile _profileConnectingTo(
  MockWebSocket socket, {
  List<String>? capturedUrls,
}) => SamsungTizenProfile(
  connect: (url, {customClient}) async {
    capturedUrls?.add(url);
    return socket;
  },
);

/// A raw `ms.channel.connect`-shaped payload as the TV sends it: the real pairing token lives at
/// `data.token`, plus the constant-valued decoy nested under `data.clients[].attributes.token`
/// that looks like a token but must never be read (see the doc comment on
/// [SamsungTizenProfile.selectInput]).
String _channelConnectMessage({String? token}) => jsonEncode({
  "event": "ms.channel.connect",
  "data": {
    "token": ?token,
    "clients": [
      {
        "attributes": {"token": "decoy-constant-token"},
      },
    ],
  },
});

void main() {
  late MockWebSocket socket;

  setUp(() {
    socket = MockWebSocket();
    when(socket.add(any)).thenAnswer((_) {});
    when(socket.close()).thenAnswer((_) async => null);
  });

  test("throws ArgumentError when host is missing", () async {
    final profile = _profileConnectingTo(socket);

    expect(
      () => profile.selectInput({"key": "KEY_HDMI1"}),
      throwsArgumentError,
    );
  });

  test("throws ArgumentError when key is missing", () async {
    final profile = _profileConnectingTo(socket);

    expect(
      () => profile.selectInput({"host": "10.10.70.1"}),
      throwsArgumentError,
    );
  });

  test("connects to the TV's secure port with a base64 client name", () async {
    final urls = <String>[];
    final profile = _profileConnectingTo(socket, capturedUrls: urls);
    when(socket.first).thenAnswer((_) async => _channelConnectMessage());

    await profile.selectInput({"host": "10.10.70.1", "key": "KEY_HDMI1"});

    expect(urls, hasLength(1));
    final uri = Uri.parse(urls.single);
    expect(uri.scheme, "wss");
    expect(uri.host, "10.10.70.1");
    expect(uri.port, 8002);
    expect(uri.queryParameters["name"], base64Encode(utf8.encode("Pitchfork")));
    expect(uri.queryParameters.containsKey("token"), isFalse);
  });

  test(
    "resends an existing token as a query param when one is already known",
    () async {
      final urls = <String>[];
      final profile = _profileConnectingTo(socket, capturedUrls: urls);
      when(socket.first).thenAnswer((_) async => _channelConnectMessage());

      await profile.selectInput({
        "host": "10.10.70.1",
        "key": "KEY_HDMI1",
        "token": "already-paired-token",
      });

      final uri = Uri.parse(urls.single);
      expect(uri.queryParameters["token"], "already-paired-token");
    },
  );

  test("sends a Click command for the configured key", () async {
    final profile = _profileConnectingTo(socket);
    when(socket.first).thenAnswer((_) async => _channelConnectMessage());

    await profile.selectInput({"host": "10.10.70.1", "key": "KEY_HDMI1"});

    final sent = jsonDecode(
      verify(socket.add(captureAny)).captured.single as String,
    ) as Map<String, dynamic>;
    expect(sent["method"], "ms.remote.control");
    expect(sent["params"], {
      "Cmd": "Click",
      "DataOfCmd": "KEY_HDMI1",
      "Option": "false",
      "TypeOfRemote": "SendRemoteKey",
    });
  });

  test(
    "throws StateError when the TV reports ms.channel.unauthorized",
    () async {
      final profile = _profileConnectingTo(socket);
      when(socket.first).thenAnswer(
        (_) async => jsonEncode({"event": "ms.channel.unauthorized"}),
      );

      await expectLater(
        () => profile.selectInput({"host": "10.10.70.1", "key": "KEY_HDMI1"}),
        throwsStateError,
      );
    },
  );

  test("returns the real pairing token from data.token, not the decoy under data.clients", () async {
    final profile = _profileConnectingTo(socket);
    when(socket.first).thenAnswer(
      (_) async => _channelConnectMessage(token: "real-pairing-token"),
    );

    final result = await profile.selectInput({
      "host": "10.10.70.1",
      "key": "KEY_HDMI1",
    });

    expect(result, {"token": "real-pairing-token"});
  });

  test("returns null when the TV's response carries no token", () async {
    final profile = _profileConnectingTo(socket);
    when(socket.first).thenAnswer((_) async => _channelConnectMessage());

    final result = await profile.selectInput({
      "host": "10.10.70.1",
      "key": "KEY_HDMI1",
    });

    expect(result, isNull);
  });

  test("closes the socket even when the TV denies the connection", () async {
    final profile = _profileConnectingTo(socket);
    when(
      socket.first,
    ).thenAnswer((_) async => jsonEncode({"event": "ms.channel.unauthorized"}));

    await expectLater(
      () => profile.selectInput({"host": "10.10.70.1", "key": "KEY_HDMI1"}),
      throwsStateError,
    );

    verify(socket.close()).called(1);
  });

  test("closes the socket on the successful path too", () async {
    final profile = _profileConnectingTo(socket);
    when(socket.first).thenAnswer((_) async => _channelConnectMessage());

    await profile.selectInput({"host": "10.10.70.1", "key": "KEY_HDMI1"});

    verify(socket.close()).called(1);
  });
}
