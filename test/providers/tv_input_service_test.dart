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

import 'package:flauncher/app_log.dart';
import 'package:flauncher/providers/tv_input/tv_input_profile.dart';
import 'package:flauncher/providers/tv_input_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FakeProfile implements TvInputProfile {
  final Future<Map<String, String>?> Function(Map<String, String> params)
  onSelectInput;

  _FakeProfile(this.onSelectInput);

  @override
  String get id => "fake";

  @override
  String get displayName => "Fake";

  @override
  List<TvInputParamSpec> get paramSpecs => const [];

  @override
  Set<String> get secretParamKeys => const {};

  @override
  Future<Map<String, String>?> selectInput(Map<String, String> params) =>
      onSelectInput(params);
}

void main() {
  setUp(() {
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.empty();
  });

  test("addInput persists and notifies", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.clear();
    final tvInputService = TvInputService(sharedPreferences, profiles: {});
    var notified = false;
    tvInputService.addListener(() => notified = true);

    await tvInputService.addInput(
      label: "Xbox",
      profileId: "fake",
      params: {"host": "10.10.70.1"},
    );

    expect(tvInputService.inputs, hasLength(1));
    expect(tvInputService.inputs.single.label, "Xbox");
    expect(tvInputService.inputs.single.params, {"host": "10.10.70.1"});
    expect(notified, isTrue);

    // Reloading from the same SharedPreferences backing store should recover the same input.
    final reloaded = TvInputService(sharedPreferences, profiles: {});
    expect(reloaded.inputs, hasLength(1));
    expect(reloaded.inputs.single.label, "Xbox");
  });

  test("removeInput drops only the matching input", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.clear();
    final tvInputService = TvInputService(sharedPreferences, profiles: {});
    await tvInputService.addInput(label: "Xbox", profileId: "fake", params: {});
    await tvInputService.addInput(
      label: "Chromecast",
      profileId: "fake",
      params: {},
    );
    final idToRemove = tvInputService.inputs.first.id;

    await tvInputService.removeInput(idToRemove);

    expect(tvInputService.inputs, hasLength(1));
    expect(tvInputService.inputs.single.label, "Chromecast");
  });

  test(
    "select dispatches to the matching profile with the input's params",
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      Map<String, String>? receivedParams;
      final fakeProfile = _FakeProfile((params) async {
        receivedParams = params;
        return null;
      });
      final tvInputService = TvInputService(
        sharedPreferences,
        profiles: {"fake": fakeProfile},
      );
      await tvInputService.addInput(
        label: "Xbox",
        profileId: "fake",
        params: {"key": "KEY_HDMI1"},
      );

      await tvInputService.select(tvInputService.inputs.single);

      expect(receivedParams, {"key": "KEY_HDMI1"});
    },
  );

  test(
    "select persists params the profile returns (e.g. a pairing token)",
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final fakeProfile = _FakeProfile((params) async => {"token": "abc123"});
      final tvInputService = TvInputService(
        sharedPreferences,
        profiles: {"fake": fakeProfile},
      );
      await tvInputService.addInput(
        label: "Xbox",
        profileId: "fake",
        params: {"host": "10.10.70.1"},
      );

      await tvInputService.select(tvInputService.inputs.single);

      expect(tvInputService.inputs.single.params, {
        "host": "10.10.70.1",
        "token": "abc123",
      });
    },
  );

  test(
    "select shares the returned token across every input for the same host",
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final fakeProfile = _FakeProfile((params) async => {"token": "abc123"});
      final tvInputService = TvInputService(
        sharedPreferences,
        profiles: {"fake": fakeProfile},
      );
      await tvInputService.addInput(
        label: "Xbox",
        profileId: "fake",
        params: {"host": "10.10.70.1", "key": "KEY_HDMI1"},
      );
      await tvInputService.addInput(
        label: "Chromecast",
        profileId: "fake",
        params: {"host": "10.10.70.1", "key": "KEY_HDMI2"},
      );
      await tvInputService.addInput(
        label: "Other TV",
        profileId: "fake",
        params: {"host": "10.10.70.2", "key": "KEY_HDMI1"},
      );

      await tvInputService.select(
        tvInputService.inputs.firstWhere((i) => i.label == "Xbox"),
      );

      expect(
        tvInputService.inputs
            .firstWhere((i) => i.label == "Chromecast")
            .params["token"],
        "abc123",
        reason: "same host as Xbox -- should pick up the same token",
      );
      expect(
        tvInputService.inputs
            .firstWhere((i) => i.label == "Other TV")
            .params
            .containsKey("token"),
        isFalse,
        reason: "different host -- must not receive Xbox's token",
      );
    },
  );

  test(
    "select logs to AppLog instead of throwing when the profile fails",
    () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final fakeProfile = _FakeProfile(
        (_) async => throw StateError("TV unreachable"),
      );
      final tvInputService = TvInputService(
        sharedPreferences,
        profiles: {"fake": fakeProfile},
      );
      await tvInputService.addInput(
        label: "Xbox",
        profileId: "fake",
        params: {},
      );
      final entriesBefore = AppLog.instance.entries.length;

      await tvInputService.select(tvInputService.inputs.single);

      expect(AppLog.instance.entries.length, entriesBefore + 1);
      expect(AppLog.instance.entries.first.message, contains("TV unreachable"));
    },
  );

  test("select logs to AppLog when the input's profile is unknown", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    await sharedPreferences.clear();
    final tvInputService = TvInputService(sharedPreferences, profiles: {});
    await tvInputService.addInput(
      label: "Xbox",
      profileId: "missing",
      params: {},
    );
    final entriesBefore = AppLog.instance.entries.length;

    await tvInputService.select(tvInputService.inputs.single);

    expect(AppLog.instance.entries.length, entriesBefore + 1);
    expect(AppLog.instance.entries.first.message, contains("Unknown profile"));
  });
}
