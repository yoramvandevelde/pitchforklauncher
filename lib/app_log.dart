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

import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime timestamp;
  final String source;
  final String message;

  const LogEntry({required this.timestamp, required this.source, required this.message});

  @override
  String toString() {
    final t = timestamp.toIso8601String().substring(11, 19);
    return "$t [$source] $message";
  }
}

/// Rudimentary in-memory error log surfaced to the user via FLauncherAboutDialog's "Logs" button.
/// Not persisted across app restarts -- this is meant to help a user explain a support issue
/// ("my wallpaper won't load"), not to be a full crash-reporting solution.
class AppLog extends ChangeNotifier {
  static const _maxEntries = 50;

  static final AppLog instance = AppLog._();

  AppLog._();

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(String source, Object message) {
    _entries.insert(0, LogEntry(timestamp: DateTime.now(), source: source, message: message.toString()));
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
  }
}
