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

import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flauncher/app_log.dart';
import 'package:flauncher/providers/tv_input/tv_input_profile.dart';
import 'package:flauncher/providers/tv_input/tv_input_profiles.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tvInputsKey = "tv_inputs";

class TvInputConfig {
  final String id;
  final String label;
  final String profileId;
  final Map<String, String> params;

  const TvInputConfig({
    required this.id,
    required this.label,
    required this.profileId,
    required this.params,
  });

  /// [excludeParamKeys] strips the given keys from [params] -- used by the settings-backup export
  /// to omit secrets like a TV's pairing token (see [TvInputProfile.secretParamKeys]) without
  /// touching the live, in-app copy this method is also used for.
  Map<String, dynamic> toJson({Set<String> excludeParamKeys = const {}}) => {
    "id": id,
    "label": label,
    "profileId": profileId,
    "params": excludeParamKeys.isEmpty
        ? params
        : (Map<String, String>.from(params)..removeWhere((key, _) => excludeParamKeys.contains(key))),
  };

  factory TvInputConfig.fromJson(Map<String, dynamic> json) => TvInputConfig(
    id: json["id"] as String,
    label: json["label"] as String,
    profileId: json["profileId"] as String,
    params: Map<String, String>.from(json["params"] as Map),
  );
}

/// Owns the user-configured list of "things I can switch the TV to" (e.g. "Xbox") and dispatches
/// selection to the right [TvInputProfile]. A short, rarely-changing list, so it's persisted as a
/// JSON blob in [SharedPreferences] rather than a Drift table -- see [SettingsService] for the
/// same storage choice on similarly simple state.
class TvInputService extends ChangeNotifier {
  final SharedPreferences _sharedPreferences;

  /// The profile registry to dispatch [select] through. Defaults to the real [tvInputProfiles]
  /// (production), but overridable in tests so dispatch/error-logging can be verified against a
  /// fake [TvInputProfile] instead of hitting the network.
  final Map<String, TvInputProfile> _profiles;

  static final _random = Random();

  List<TvInputConfig> _inputs = [];

  /// Ids of inputs with a [select] currently in flight. A rapid repeated press (mashing the
  /// button while the TV hasn't responded yet) was piling up multiple simultaneous connection
  /// attempts against the same TV, which some TVs can't service concurrently -- they'd all time
  /// out, and each one also showed as a separate pending pairing request. This guard makes a
  /// repeat press while one is already running a no-op instead.
  final Set<String> _selecting = {};

  List<TvInputConfig> get inputs => UnmodifiableListView(_inputs);

  TvInputService(
    this._sharedPreferences, {
    Map<String, TvInputProfile>? profiles,
  }) : _profiles = profiles ?? tvInputProfiles {
    final raw = _sharedPreferences.getString(_tvInputsKey);
    if (raw != null) {
      _inputs = (jsonDecode(raw) as List)
          .map((e) => TvInputConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> addInput({
    required String label,
    required String profileId,
    required Map<String, String> params,
  }) {
    final id =
        "${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}";
    _inputs = [
      ..._inputs,
      TvInputConfig(id: id, label: label, profileId: profileId, params: params),
    ];
    return _persist();
  }

  Future<void> removeInput(String id) {
    _inputs = _inputs.where((input) => input.id != id).toList();
    return _persist();
  }

  /// Wholesale replaces the configured inputs, e.g. from a settings restore. Unlike [addInput]/
  /// [removeInput], which build on the current list, this discards it entirely.
  Future<void> replaceAll(List<TvInputConfig> inputs) {
    _inputs = inputs;
    return _persist();
  }

  Future<void> _persist() async {
    await _sharedPreferences.setString(
      _tvInputsKey,
      jsonEncode(_inputs.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// Resolves [config]'s profile and asks it to switch the TV. Failures (TV offline, pairing
  /// declined, ...) are logged via [AppLog] rather than thrown -- a bad TV/network hiccup
  /// shouldn't crash the launcher, just leave a trace the user can check.
  Future<void> select(TvInputConfig config) async {
    if (!_selecting.add(config.id)) {
      return;
    }
    try {
      final profile = _profiles[config.profileId];
      if (profile == null) {
        AppLog.instance.log(
          "TvInput",
          "Unknown profile '${config.profileId}' for input '${config.label}'",
        );
        return;
      }
      try {
        final updatedParams = await profile.selectInput(config.params);
        if (updatedParams != null) {
          await _updateInputParamsForHost(
            config.profileId,
            config.params["host"],
            updatedParams,
          );
        }
      } catch (e, st) {
        AppLog.instance.log(
          "TvInput",
          "Failed to switch to '${config.label}': $e\n$st",
        );
      }
    } finally {
      _selecting.remove(config.id);
    }
  }

  /// Merges [params] onto every input for [profileId] whose own "host" param matches [host] --
  /// not just the one that was pressed. A pairing token (see SamsungTizenProfile) is issued per
  /// TV, not per button: the TV recognizes the connecting client by name regardless of which
  /// locally-configured input triggered the connection, so every input pointing at the same TV
  /// needs to share the same token or each one re-triggers its own "Allow access?" prompt the
  /// first time it's pressed, even after another input to the same TV already paired.
  Future<void> _updateInputParamsForHost(
    String profileId,
    String? host,
    Map<String, String> params,
  ) {
    _inputs = [
      for (final input in _inputs)
        if (input.profileId == profileId && input.params["host"] == host)
          TvInputConfig(
            id: input.id,
            label: input.label,
            profileId: input.profileId,
            params: {...input.params, ...params},
          )
        else
          input,
    ];
    return _persist();
  }
}
