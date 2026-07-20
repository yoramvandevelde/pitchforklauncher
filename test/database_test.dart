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
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;

void main() {
  late FLauncherDatabase database;
  setUp(() {
    database = FLauncherDatabase.inMemory();
  });

  tearDown(() async {
    await database.close();
  });

  test("listApplications", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");

    final apps = await database.listApplications();

    expect(apps.length, 1);
    expect(apps[0].packageName, "io.sifft.pitchforklauncher");
    expect(apps[0].name, "FLauncher");
    expect(apps[0].version, "1.0.0");
    expect(apps[0].banner, null);
    expect(apps[0].icon, null);
  });

  test("persistApps", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    await database.persistApps(
        [AppsCompanion.insert(packageName: "io.sifft.pitchforklauncher", name: "FLauncher 2", version: "1.1.0")]);

    final app = await database.customSelect("SELECT * FROM apps;").getSingle();
    expect(app.read<String>("package_name"), "io.sifft.pitchforklauncher");
    expect(app.read<String>("name"), "FLauncher 2");
    expect(app.read<String>("version"), "1.1.0");
    expect(app.read<Uint8List?>("banner"), null);
    expect(app.read<Uint8List?>("icon"), null);
  });

  test("updateApp", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon, hidden)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null, false);");
    await database.updateApp("io.sifft.pitchforklauncher", AppsCompanion(hidden: Value(true)));

    final app = await database.customSelect("SELECT * FROM apps;").getSingle();
    expect(app.read<String>("package_name"), "io.sifft.pitchforklauncher");
    expect(app.read<String>("name"), "FLauncher");
    expect(app.read<String>("version"), "1.0.0");
    expect(app.read<Uint8List?>("banner"), null);
    expect(app.read<Uint8List?>("icon"), null);
    expect(app.read<bool>("hidden"), true);
  });

  test("deleteApps", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher.2', 'FLauncher 2', '1.0.0', null, null);");

    await database.deleteApps(["io.sifft.pitchforklauncher"]);

    final app = await database.customSelect("SELECT * FROM apps;").getSingle();
    expect(app.read<String>("package_name"), "io.sifft.pitchforklauncher.2");
  });

  test("insertCategory", () async {
    await database.insertCategory(CategoriesCompanion.insert(name: "Test", order: 2));

    final category = await database.customSelect("SELECT * FROM categories WHERE name = 'Test';").getSingle();
    expect(category.read<String>("name"), "Test");
    expect(category.read<int>("order"), 2);
  });

  test("deleteCategory", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher', 0);");

    await database.deleteCategory(categoryId);

    final app = await database.customSelect("SELECT * FROM apps;").getSingle();
    expect(app.read<String>("package_name"), "io.sifft.pitchforklauncher");
    final appsCategories = await database.customSelect("SELECT * FROM apps_categories;").get();
    expect(appsCategories, isEmpty);
    final categories = await database.customSelect("SELECT * FROM categories c ORDER BY c.'order' ASC;").get();
    expect(categories, isEmpty);
  });

  test("updateCategories", () async {
    final test1Id = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test 1', 2);");
    final test2Id = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test 2', 3);");

    await database.updateCategories([
      CategoriesCompanion(id: Value(test2Id), order: Value(2)),
      CategoriesCompanion(id: Value(test1Id), order: Value(3)),
    ]);

    final categories = await database.customSelect("SELECT * FROM categories c ORDER BY c.'order' ASC;").get();
    expect(categories.length, 2);
    expect(categories[0].read<String>("name"), "Test 2");
    expect(categories[1].read<String>("name"), "Test 1");
  });

  test("updateCategory", () async {
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");

    await database.updateCategory(categoryId, CategoriesCompanion(order: Value(5)));

    final categories = await database.customSelect("SELECT * FROM categories c ORDER BY c.'order' ASC;").get();
    expect(categories.length, 1);
    expect(categories[0].read<String>("name"), "Test");
    expect(categories[0].read<int>("order"), 5);
  });

  test("deleteAppCategory", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher', 0);");

    await database.deleteAppCategory(categoryId, "io.sifft.pitchforklauncher");

    final app = await database.customSelect("SELECT * FROM apps;").getSingle();
    expect(app.read<String>("package_name"), "io.sifft.pitchforklauncher");
    final appsCategories = await database.customSelect("SELECT * FROM apps_categories;").get();
    expect(appsCategories, isEmpty);
    final categories = await database.customSelect("SELECT * FROM categories c ORDER BY c.'order' ASC;").get();
    expect(categories.length, 1);
    expect(categories[0].read<String>("name"), "Test");
  });

  test("insertAppsCategories", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order')"
        " VALUES('Test', 2);");
    await database.insertAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: categoryId, appPackageName: "io.sifft.pitchforklauncher", order: 0),
    ]);

    final appCategory = await database.customSelect("SELECT * FROM apps_categories;").getSingle();
    expect(appCategory.read<int>("category_id"), categoryId);
    expect(appCategory.read<String>("app_package_name"), "io.sifft.pitchforklauncher");
    expect(appCategory.read<int>("order"), 0);
  });

  test("replaceAppsCategories", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher', 0);");

    await database.replaceAppsCategories(
        [AppsCategoriesCompanion.insert(categoryId: categoryId, appPackageName: "io.sifft.pitchforklauncher", order: 1)]);

    final appCategory = await database.customSelect("SELECT * FROM apps_categories;").getSingle();
    expect(appCategory.read<int>("category_id"), categoryId);
    expect(appCategory.read<String>("app_package_name"), "io.sifft.pitchforklauncher");
    expect(appCategory.read<int>("order"), 1);
  });

  test("listCategoriesWithApps", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher.2', 'FLauncher 2', '1.0.0', null, null);");
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon, hidden)"
        " VALUES('io.sifft.pitchforklauncher.3', 'FLauncher 3', '1.0.0', null, null, true);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher', 1);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher.2', 0);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher.3', 2);");

    final categoriesWithApps = await database.listCategoriesWithVisibleApps();

    expect(categoriesWithApps.length, 1);
    expect(categoriesWithApps[0].category.name, "Test");
    expect(categoriesWithApps[0].applications.length, 2);
    expect(categoriesWithApps[0].applications[0].packageName, "io.sifft.pitchforklauncher.2");
    expect(categoriesWithApps[0].applications[0].name, "FLauncher 2");
    expect(categoriesWithApps[0].applications[1].packageName, "io.sifft.pitchforklauncher");
    expect(categoriesWithApps[0].applications[1].name, "FLauncher");
  });

  test("nextAppCategoryOrder", () async {
    await database.customInsert("INSERT INTO apps(package_name, name, version, banner, icon)"
        " VALUES('io.sifft.pitchforklauncher', 'FLauncher', '1.0.0', null, null);");
    final categoryId = await database.customInsert("INSERT INTO categories(name, 'order') VALUES('Test', 2);");
    await database.customInsert("INSERT INTO apps_categories(category_id, app_package_name, 'order')"
        " VALUES($categoryId, 'io.sifft.pitchforklauncher', 1);");

    final index = await database.nextAppCategoryOrder(categoryId);

    expect(index, 2);
  });
}
