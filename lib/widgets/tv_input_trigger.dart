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

import 'package:flauncher/widgets/tv_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _holdDuration = Duration(seconds: 1);

/// Wraps the homescreen so holding D-pad Up for [_holdDuration] opens [TvInputBar]. Below the
/// threshold every event is ignored, so it bubbles up to the normal DirectionalFocusIntent
/// handling untouched -- short presses/holds behave exactly as they do without this widget. Once
/// the threshold fires, further repeats of that same key-down are swallowed (reset on key-up) so
/// the triggering hold doesn't also spam focus navigation upward while the bar opens. Opens
/// regardless of whether any input is configured yet -- [TvInputBar] itself shows a shortcut to
/// TvInputsPanelPage when the list is empty, so the gesture doubles as a discovery path.
class TvInputTrigger extends StatefulWidget {
  final Widget child;

  const TvInputTrigger({super.key, required this.child});

  @override
  State<TvInputTrigger> createState() => _TvInputTriggerState();
}

class _TvInputTriggerState extends State<TvInputTrigger> {
  int? _keyDownAt;
  bool _fired = false;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _handleKey,
    child: widget.child,
  );

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) {
      _keyDownAt = null;
      _fired = false;
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _keyDownAt = DateTime.now().millisecondsSinceEpoch;
      _fired = false;
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) {
      if (_fired) {
        return KeyEventResult.handled;
      }
      final keyDownAt = _keyDownAt;
      if (keyDownAt == null ||
          DateTime.now().millisecondsSinceEpoch - keyDownAt <
              _holdDuration.inMilliseconds) {
        return KeyEventResult.ignored;
      }
      _fired = true;
      Navigator.of(context, rootNavigator: true).push(TvInputBar.route());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
