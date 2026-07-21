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
import 'package:flauncher/widgets/ensure_visible.dart';
import 'package:flauncher/widgets/settings/category_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoriesPanelPage extends StatefulWidget {
  static const String routeName = "categories_panel";

  @override
  State<CategoriesPanelPage> createState() => _CategoriesPanelPageState();
}

class _CategoriesPanelPageState extends State<CategoriesPanelPage> {
  final Map<int, FocusNode> _upFocusNodes = {};
  final Map<int, FocusNode> _downFocusNodes = {};

  @override
  void dispose() {
    for (final node in _upFocusNodes.values) {
      node.dispose();
    }
    for (final node in _downFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _upFocusNode(int categoryId) => _upFocusNodes.putIfAbsent(categoryId, () => FocusNode());

  FocusNode _downFocusNode(int categoryId) => _downFocusNodes.putIfAbsent(categoryId, () => FocusNode());

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text("Categories", style: Theme.of(context).textTheme.titleLarge),
          Divider(),
          Selector<AppsService, List<CategoryWithApps>>(
            selector: (_, appsService) => appsService.categoriesWithApps,
            builder: (_, categories, _) => Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: categories.asMap().keys.map((index) => _category(context, categories, index)).toList(),
                ),
              ),
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.add),
            label: Text("Add Category"),
            onPressed: () async {
              final categoryName = await showDialog<String>(context: context, builder: (_) => AddCategoryDialog());
              if (categoryName != null) {
                await context.read<AppsService>().addCategory(categoryName);
              }
            },
          ),
        ],
      );

  Widget _category(BuildContext context, List<CategoryWithApps> categories, int index) {
    final categoryId = categories[index].category.id;
    return Padding(
      key: Key(categoryId.toString()),
      padding: EdgeInsets.only(bottom: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: EnsureVisible(
          alignment: 0.5,
          child: ListTile(
            dense: true,
            title: Text(categories[index].category.name, style: Theme.of(context).textTheme.bodyMedium),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  focusNode: _upFocusNode(categoryId),
                  constraints: BoxConstraints(),
                  splashRadius: 20,
                  icon: Icon(Icons.arrow_upward),
                  onPressed:
                      index > 0 ? () => _move(context, categories.length, categoryId, index, index - 1) : null,
                ),
                IconButton(
                  focusNode: _downFocusNode(categoryId),
                  constraints: BoxConstraints(),
                  splashRadius: 20,
                  icon: Icon(Icons.arrow_downward),
                  onPressed: index < categories.length - 1
                      ? () => _move(context, categories.length, categoryId, index, index + 1)
                      : null,
                ),
                IconButton(
                  constraints: BoxConstraints(),
                  splashRadius: 20,
                  icon: Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).pushNamed(
                    CategoryPanelPage.routeName,
                    arguments: categories[index].category.id,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _move(BuildContext context, int categoriesCount, int categoryId, int oldIndex, int newIndex) async {
    await context.read<AppsService>().moveCategory(oldIndex, newIndex);
    if (!mounted) return;

    // A row landing on an extreme disables the arrow the user just pressed, and Flutter's
    // disabled-widget fallback hands focus to the next traversal stop ("Add Category") instead
    // of somewhere sensible. Explicitly refocus the row's remaining enabled arrow after the
    // rebuild settles.
    final FocusNode? nodeToRefocus =
        newIndex == 0 ? _downFocusNode(categoryId) : (newIndex == categoriesCount - 1 ? _upFocusNode(categoryId) : null);
    if (nodeToRefocus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          nodeToRefocus.requestFocus();
        }
      });
    }
  }
}
