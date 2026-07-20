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

/// Git branch/commit baked in at build time via --dart-define (see justfile's
/// build-install recipe). Falls back to "unknown" for builds that don't pass it
/// (e.g. a raw `flutter run` outside that recipe).
class BuildInfo {
  static const gitBranch = String.fromEnvironment('GIT_BRANCH', defaultValue: 'unknown');
  static const gitCommit = String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown');
}
