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
import 'dart:io';

import 'package:flauncher/providers/tv_input/tv_input_profile.dart';

/// Talks to a Samsung Tizen TV's local WebSocket remote-control API (present on Tizen models
/// since ~2016) to send a single remote key press -- no companion app, no root, just the TV's
/// own LAN-only control channel.
///
/// Uses the secure port (8002, self-signed cert) rather than the legacy plaintext one (8001):
/// newer Tizen firmware silently rejects plaintext pairing attempts with `ms.channel.unauthorized`
/// without ever showing the "Allow access?" prompt or adding the client to the TV's device list,
/// regardless of the TV's notification settings -- confirmed against a 2019 model. The TLS
/// handshake is against a self-signed cert (there's no CA involved for a LAN-only device control
/// channel), so certificate validation is intentionally bypassed here.
///
/// The first connection from a given client name pops an "Allow access?" prompt on the TV; on
/// approval the TV hands back a pairing token that must be resent on every later connection (see
/// [selectInput]'s return value) for the TV to recognize this as the same already-approved client
/// instead of prompting again.
class SamsungTizenProfile implements TvInputProfile {
  static const _appName = "Pitchfork";
  static const _port = 8002;
  static const _connectTimeout = Duration(seconds: 5);

  // Separate, much longer timeout for the TV's response to the connection attempt: the first
  // message only arrives once the "Allow access?" prompt has been resolved on the TV, which
  // depends on a human physically reacting to it -- 5s (fine for the raw TCP/WS handshake) isn't
  // enough time for someone to even notice the prompt, let alone grab the remote and press Allow.
  // Timing out here closes the socket mid-prompt, which some TVs then remember as a denial, so
  // this was silently poisoning the TV's paired-device list for future attempts too.
  static const _pairingTimeout = Duration(seconds: 30);

  @override
  String get id => "samsung_tizen";

  @override
  String get displayName => "Samsung (Tizen)";

  @override
  List<TvInputParamSpec> get paramSpecs => const [
    TvInputParamSpec(key: "host", label: "TV IP address"),
    TvInputParamSpec(key: "key", label: "Remote key code (e.g. KEY_HDMI)"),
  ];

  @override
  Future<Map<String, String>?> selectInput(Map<String, String> params) async {
    final host = params["host"];
    final key = params["key"];
    if (host == null || host.isEmpty || key == null || key.isEmpty) {
      throw ArgumentError(
        "Samsung profile requires both 'host' and 'key' params",
      );
    }
    final name = base64Encode(utf8.encode(_appName));
    final existingToken = params["token"];
    final uri =
        "wss://$host:$_port/api/v2/channels/samsung.remote.control?name=$name"
        "${existingToken != null ? '&token=$existingToken' : ''}";
    // The TV's cert is self-signed with no CA chain -- accepting it unconditionally is fine here
    // since this is a LAN-only device control channel, not a connection to an untrusted host.
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    final socket = await WebSocket.connect(
      uri,
      customClient: httpClient,
    ).timeout(_connectTimeout);
    try {
      // The TV sends an ms.channel.connect (or .unauthorized) event as soon as the connection is
      // accepted -- waiting for it means the key press can't fire before the "Allow access?"
      // prompt has actually been resolved.
      final firstMessage = await socket.first.timeout(_pairingTimeout);
      final data = jsonDecode(firstMessage as String) as Map<String, dynamic>;
      if (data["event"] == "ms.channel.unauthorized") {
        throw StateError(
          "TV denied the connection (declined the pairing prompt?)",
        );
      }
      final command = jsonEncode({
        "method": "ms.remote.control",
        "params": {
          "Cmd": "Click",
          "DataOfCmd": key,
          "Option": "false",
          "TypeOfRemote": "SendRemoteKey",
        },
      });
      socket.add(command);
      // Give the write time to actually reach the TV over TLS before tearing the socket down --
      // add() queues the frame but doesn't guarantee it's been flushed to the network yet, and an
      // immediate close() risked cutting the command off mid-send.
      await Future<void>.delayed(const Duration(seconds: 1));
      // ms.channel.connect's data.token is what the official samsungtvws client (which
      // HomeAssistant's Samsung integration wraps) reads and persists for reuse -- confirmed by
      // reading its connection.py directly. This response also has a *different*, decoy-looking
      // token nested under data.clients[].attributes.token that stays constant across calls;
      // resending that one (which an earlier version of this code did) is why the TV kept
      // re-prompting even though the value "looked" like a stable pairing token.
      final newToken =
          (data["data"] as Map<String, dynamic>?)?["token"] as String?;
      // Always report the token back, even when it's unchanged from what this input already had
      // -- TvInputService broadcasts it to every input sharing this host, and gating on "changed"
      // meant a sibling input added after this one had already paired never got healed onto the
      // shared token, since nothing here re-fired once the token stopped visibly changing.
      if (newToken != null) {
        return {"token": newToken};
      }
      return null;
    } finally {
      await socket.close();
      httpClient.close();
    }
  }
}
