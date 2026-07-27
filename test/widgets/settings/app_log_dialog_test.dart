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
import 'package:flauncher/widgets/settings/app_log_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("arrow keys scroll the log via the D-pad, without needing a focusable list item", (tester) async {
    // Enough long entries to overflow the dialog's fixed 400px content height.
    for (var i = 0; i < 30; i++) {
      AppLog.instance.log("Picsum", "PicsumException: boom $i\n#0 someFunction (package:flauncher/foo.dart:1:1)\n"
          "#1 anotherFunction (package:flauncher/bar.dart:2:2)");
    }

    await tester.pumpWidget(MaterialApp(home: AppLogDialog()));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const Key("app_log_scroll_view")), matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.pixels, 0);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}
