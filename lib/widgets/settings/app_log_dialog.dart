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

import 'package:flauncher/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLogDialog extends StatefulWidget {
  const AppLogDialog({super.key});

  @override
  State<AppLogDialog> createState() => _AppLogDialogState();
}

class _AppLogDialogState extends State<AppLogDialog> {
  static const _scrollStep = 80.0;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final double direction;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      direction = 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      direction = -1;
    } else {
      return KeyEventResult.ignored;
    }
    final offset = _scrollController.offset;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if ((direction > 0 && offset >= maxExtent) || (direction < 0 && offset <= 0)) {
      // Already at that end -- let normal directional focus traversal take over (e.g. reaching
      // the Close button below) instead of eating the key with nothing left to scroll.
      return KeyEventResult.ignored;
    }
    final target = (offset + direction * _scrollStep).clamp(0.0, maxExtent);
    _scrollController.animateTo(target, duration: Duration(milliseconds: 100), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text("Logs"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListenableBuilder(
            listenable: AppLog.instance,
            builder: (context, _) {
              final entries = AppLog.instance.entries;
              if (entries.isEmpty) {
                return Text("No errors logged since the app was last started.");
              }
              return Focus(
                autofocus: true,
                onKeyEvent: _handleKey,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const Key("app_log_scroll_view"),
                    controller: _scrollController,
                    child: Text(
                      entries.join("\n\n"),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: "monospace"),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Close"),
          ),
        ],
      );
}
