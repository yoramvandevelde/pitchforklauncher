/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/database.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/add_category_dialog.dart';
import 'package:flauncher/widgets/settings/categories_panel_page.dart';
import 'package:flauncher/widgets/settings/category_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("Categories are displayed", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites"), []),
      CategoryWithApps(fakeCategory(name: "Applications"), []),
    ]);

    await _pumpWidgetWithProviders(tester, appsService);

    expect(find.text("Favorites"), findsOneWidget);
    expect(find.text("Applications"), findsOneWidget);
  });

  testWidgets("'Arrow down' change category order", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites"), []),
      CategoryWithApps(fakeCategory(name: "Applications"), []),
    ]);
    await _pumpWidgetWithProviders(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    verify(appsService.moveCategory(0, 1));
    expect(find.text("Favorites"), findsOneWidget);
    expect(find.text("Applications"), findsOneWidget);
  });

  testWidgets("Moving a category to the bottom of a 2-item list keeps focus off 'Add Category'", (tester) async {
    final appsService = MockAppsService();
    var categories = [
      CategoryWithApps(fakeCategory(name: "Favorites"), []),
      CategoryWithApps(fakeCategory(name: "Applications"), []),
    ];
    when(appsService.categoriesWithApps).thenAnswer((_) => categories);

    // MockAppsService only `implements` AppsService, so its notifyListeners()/addListener() are
    // no-op Mockito stubs rather than real ChangeNotifier plumbing. Capture the listener that
    // ChangeNotifierProvider registers so we can invoke it ourselves to simulate a real
    // notifyListeners() call after moveCategory reorders the list.
    final listeners = <VoidCallback>[];
    when(appsService.addListener(any)).thenAnswer((invocation) {
      listeners.add(invocation.positionalArguments[0] as VoidCallback);
    });
    when(appsService.moveCategory(any, any)).thenAnswer((invocation) async {
      final oldIndex = invocation.positionalArguments[0] as int;
      final newIndex = invocation.positionalArguments[1] as int;
      // A new list instance, matching how the real AppsService re-fetches from the database after
      // a move — Selector's change detection relies on identity, so mutating in place wouldn't
      // trigger a rebuild here the way it does in production.
      final movedCategory = categories[oldIndex];
      categories = List.of(categories)
        ..removeAt(oldIndex)
        ..insert(newIndex, movedCategory);
      for (final listener in List.of(listeners)) {
        listener();
      }
    });
    await _pumpWidgetWithProviders(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    verify(appsService.moveCategory(0, 1));

    final addCategoryFocusNode = Focus.of(tester.element(find.text("Add Category")));
    expect(addCategoryFocusNode.hasFocus, isFalse);

    final favoritesUpArrow = find.descendant(
      of: find.ancestor(of: find.text("Favorites"), matching: find.byType(Card)),
      matching: find.byIcon(Icons.arrow_upward),
    );
    final favoritesUpArrowFocusNode = Focus.of(tester.element(favoritesUpArrow));
    expect(favoritesUpArrowFocusNode.hasFocus, isTrue);
  });

  testWidgets("'Settings' opens CategoryPanelPage", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites"), []),
      CategoryWithApps(fakeCategory(name: "Applications"), []),
    ]);
    await _pumpWidgetWithProviders(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(Key("CategoryPanelPage")), findsOneWidget);
  });

  testWidgets("'Add Category' opens AddCategoryDialog", (tester) async {
    final appsService = MockAppsService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites"), []),
      CategoryWithApps(fakeCategory(name: "Applications"), []),
    ]);
    await _pumpWidgetWithProviders(tester, appsService);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(AddCategoryDialog), findsOneWidget);
  });
}

Future<void> _pumpWidgetWithProviders(WidgetTester tester, AppsService appsService) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppsService>.value(value: appsService),
      ],
      builder: (_, _) => MaterialApp(
        routes: {
          CategoryPanelPage.routeName: (_) => Container(key: Key("CategoryPanelPage")),
        },
        home: Scaffold(body: CategoriesPanelPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
