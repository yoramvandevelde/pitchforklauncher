/*
 * PitchforkLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/default_app_categories.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  // _initDefaultCategories() reads this to exclude PitchforkLauncher's own package from the
  // automatic seed -- see the "excludes PitchforkLauncher's own package" test below.
  setUpAll(() {
    PackageInfoPlatform.instance = _MockPackageInfoPlatform();
  });

  group("AppsService initialised correctly", () {
    test("with empty database", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'com.example.app',
              'name': 'FLauncher',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
            {
              'packageName': 'com.example.app2',
              'name': 'FLauncher 2',
              'version': '2.0.0',
              'banner': null,
              'icon': null,
              'sideloaded': true
            }
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "com.example.app",
              name: "FLauncher",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
            fakeApp(
              packageName: "com.example.app2",
              name: "FLauncher 2",
              version: "2.0.0",
              banner: null,
              icon: null,
              sideloaded: true,
            ),
          ]));
      final tvApplicationsCategory = fakeCategory(name: "TV Applications");
      final nonTvApplicationsCategory = fakeCategory(name: "Non-TV Applications");
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(tvApplicationsCategory, []),
            CategoryWithApps(nonTvApplicationsCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyInOrder([
        database.listApplications(),
        database.persistApps([
          AppsCompanion.insert(
            packageName: "com.example.app",
            name: "FLauncher",
            version: "(unknown)",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          ),
          AppsCompanion.insert(
            packageName: "com.example.app2",
            name: "FLauncher 2",
            version: "2.0.0",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(true),
          ),
        ]),
        database.deleteApps([]),
        database.listCategoriesWithVisibleApps(),
        database.listApplications(),
        database.insertCategory(
          CategoriesCompanion.insert(name: "TV Applications", order: 0),
        ),
        database.updateCategory(
          tvApplicationsCategory.id,
          CategoriesCompanion(type: Value(CategoryType.row)),
        ),
        database.updateCategory(
          tvApplicationsCategory.id,
          CategoriesCompanion(rowHeight: Value(80)),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: tvApplicationsCategory.id,
            appPackageName: "com.example.app",
            order: 0,
          )
        ]),
        database.insertCategory(
          CategoriesCompanion.insert(name: "Non-TV Applications", order: 0),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: nonTvApplicationsCategory.id,
            appPackageName: "com.example.app2",
            order: 0,
          )
        ]),
        database.listCategoriesWithVisibleApps(),
      ]);
    });

    test("excludes PitchforkLauncher's own package from the default category seed", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'io.sifft.pitchforklauncher',
              'name': 'PitchforkLauncher',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false,
            },
            {
              'packageName': 'com.example.app',
              'name': 'Some App',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false,
            },
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "io.sifft.pitchforklauncher",
              name: "PitchforkLauncher",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
            fakeApp(
              packageName: "com.example.app",
              name: "Some App",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
          ]));
      final tvApplicationsCategory = fakeCategory(name: "TV Applications");
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(tvApplicationsCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      // Both apps get persisted to the apps table (still shows up in the Applications panel like
      // any other installed app) -- only the category seed skips its own package.
      verify(database.persistApps([
        AppsCompanion.insert(
          packageName: "io.sifft.pitchforklauncher",
          name: "PitchforkLauncher",
          version: "(unknown)",
          banner: Value(null),
          icon: Value(null),
          sideloaded: Value(false),
        ),
        AppsCompanion.insert(
          packageName: "com.example.app",
          name: "Some App",
          version: "(unknown)",
          banner: Value(null),
          icon: Value(null),
          sideloaded: Value(false),
        ),
      ]));
      verify(database.insertAppsCategories([
        AppsCategoriesCompanion.insert(
          categoryId: tvApplicationsCategory.id,
          appPackageName: "com.example.app",
          order: 0,
        )
      ]));
      verifyNever(database.insertAppsCategories([
        AppsCategoriesCompanion.insert(
          categoryId: tvApplicationsCategory.id,
          appPackageName: "io.sifft.pitchforklauncher",
          order: 0,
        )
      ]));
    });

    test("sorts matched apps into topical categories, falling back to TV/Non-TV split", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'com.netflix.ninja',
              'name': 'Netflix',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
            {
              'packageName': 'com.example.app',
              'name': 'FLauncher',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
            {
              'packageName': 'com.example.app2',
              'name': 'FLauncher 2',
              'version': '2.0.0',
              'banner': null,
              'icon': null,
              'sideloaded': true
            }
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "com.netflix.ninja",
              name: "Netflix",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
            fakeApp(
              packageName: "com.example.app",
              name: "FLauncher",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
            fakeApp(
              packageName: "com.example.app2",
              name: "FLauncher 2",
              version: "2.0.0",
              banner: null,
              icon: null,
              sideloaded: true,
            ),
          ]));
      // Read from the actual map rather than hardcoding a category name, so this test doesn't go
      // stale whenever default_app_categories.dart's entries get edited/reorganized.
      final matchedCategoryName = defaultAppCategories["com.netflix.ninja"]!;
      final tvApplicationsCategory = fakeCategory(name: "TV Applications");
      final nonTvApplicationsCategory = fakeCategory(name: "Non-TV Applications");
      final matchedCategory = fakeCategory(name: matchedCategoryName);
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(tvApplicationsCategory, []),
            CategoryWithApps(nonTvApplicationsCategory, []),
            CategoryWithApps(matchedCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      // The matched category is added last (after the TV/Non-TV fallback categories) so it ends
      // up visually above them -- addCategory() always inserts at order 0, pushing existing
      // categories down.
      verifyInOrder([
        database.insertCategory(
          CategoriesCompanion.insert(name: "TV Applications", order: 0),
        ),
        database.updateCategory(
          tvApplicationsCategory.id,
          CategoriesCompanion(type: Value(CategoryType.row)),
        ),
        database.updateCategory(
          tvApplicationsCategory.id,
          CategoriesCompanion(rowHeight: Value(80)),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: tvApplicationsCategory.id,
            appPackageName: "com.example.app",
            order: 0,
          )
        ]),
        database.insertCategory(
          CategoriesCompanion.insert(name: "Non-TV Applications", order: 0),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: nonTvApplicationsCategory.id,
            appPackageName: "com.example.app2",
            order: 0,
          )
        ]),
        database.insertCategory(
          CategoriesCompanion.insert(name: matchedCategoryName, order: 0),
        ),
        database.updateCategory(
          matchedCategory.id,
          CategoriesCompanion(type: Value(CategoryType.grid)),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: matchedCategory.id,
            appPackageName: "com.netflix.ninja",
            order: 0,
          )
        ]),
      ]);
    });

    test("sorts a matched app into the System category as a compact row", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'com.android.vending',
              'name': 'Play Store',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "com.android.vending",
              name: "Play Store",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
          ]));
      final systemCategory = fakeCategory(name: "System");
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(systemCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyInOrder([
        database.insertCategory(
          CategoriesCompanion.insert(name: "System", order: 0),
        ),
        database.updateCategory(
          systemCategory.id,
          CategoriesCompanion(type: Value(CategoryType.row)),
        ),
        database.updateCategory(
          systemCategory.id,
          CategoriesCompanion(rowHeight: Value(80)),
        ),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
            categoryId: systemCategory.id,
            appPackageName: "com.android.vending",
            order: 0,
          )
        ]),
      ]);
    });

    test("seeds the Streaming category with default_app_categories.dart's configured column count", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'com.netflix.ninja',
              'name': 'Netflix',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(
              packageName: "com.netflix.ninja",
              name: "Netflix",
              version: "1.0.0",
              banner: null,
              icon: null,
              sideloaded: false,
            ),
          ]));
      final streamingCategory = fakeCategory(name: "Streaming");
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(streamingCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      final expectedColumnsCount = defaultCategorySettings["Streaming"]!.columnsCount!;
      verify(database.updateCategory(
        streamingCategory.id,
        CategoriesCompanion(columnsCount: Value(expectedColumnsCount)),
      ));
    });

    test("categorization follows default_app_categories.dart's own order, not the device's alphabetical app order",
        () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      // Jellyfin/Plex are both "Media" -- alphabetically "Jellyfin" sorts before "Plex", but
      // default_app_categories.dart lists Plex before Jellyfin. Netflix is "Streaming", listed
      // before "Media" in the file, but must still end up visually *above* Media.
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'org.jellyfin.androidtv',
              'name': 'Jellyfin',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
            {
              'packageName': 'com.plexapp.android',
              'name': 'Plex',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
            {
              'packageName': 'com.netflix.ninja',
              'name': 'Netflix',
              'version': null,
              'banner': null,
              'icon': null,
              'sideloaded': false
            },
          ]));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(packageName: "org.jellyfin.androidtv", name: "Jellyfin", sideloaded: false),
            fakeApp(packageName: "com.plexapp.android", name: "Plex", sideloaded: false),
            fakeApp(packageName: "com.netflix.ninja", name: "Netflix", sideloaded: false),
          ]));
      final mediaCategory = fakeCategory(name: "Media");
      final streamingCategory = fakeCategory(name: "Streaming");
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
            CategoryWithApps(mediaCategory, []),
            CategoryWithApps(streamingCategory, []),
          ]));
      when(database.nextAppCategoryOrder(any)).thenAnswer((_) => Future.value(0));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(true);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      // Media is added first (file order), then Streaming last -- so Streaming ends up on top,
      // even though it's listed *before* Media in the file. Within Media, Plex is added before
      // Jellyfin, matching the file's order rather than the device's alphabetical app order.
      verifyInOrder([
        database.insertCategory(CategoriesCompanion.insert(name: "Media", order: 0)),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(categoryId: mediaCategory.id, appPackageName: "com.plexapp.android", order: 0)
        ]),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
              categoryId: mediaCategory.id, appPackageName: "org.jellyfin.androidtv", order: 0)
        ]),
        database.insertCategory(CategoriesCompanion.insert(name: "Streaming", order: 0)),
        database.insertAppsCategories([
          AppsCategoriesCompanion.insert(
              categoryId: streamingCategory.id, appPackageName: "com.netflix.ninja", order: 0)
        ]),
      ]);
    });

    test("with newly installed, uninstalled and existing apps", () async {
      final channel = MockFLauncherChannel();
      when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
      final database = MockFLauncherDatabase();
      when(channel.getApplications(any)).thenAnswer((_) => Future.value([
            {
              'packageName': 'io.sifft.pitchforklauncher',
              'name': 'FLauncher',
              'version': '2.0.0',
              'banner': null,
              'icon': null,
              'sideloaded': false,
            },
            {
              'packageName': 'io.sifft.pitchforklauncher.2',
              'name': 'FLauncher 2',
              'version': '1.0.0',
              'banner': null,
              'icon': null,
              'sideloaded': false,
            }
          ]));
      when(channel.applicationExists("uninstalled.app")).thenAnswer((_) => Future.value(false));
      when(channel.applicationExists("not.uninstalled.app")).thenAnswer((_) => Future.value(true));
      when(database.listApplications()).thenAnswer((_) => Future.value([
            fakeApp(packageName: "io.sifft.pitchforklauncher", name: "FLauncher", version: "1.0.0"),
            fakeApp(packageName: "uninstalled.app", name: "Uninstalled Application", version: "1.0.0"),
            fakeApp(packageName: "not.uninstalled.app", name: "Not Uninstalled Application", version: "1.0.0")
          ]));
      when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      AppsService(channel, database);
      await untilCalled(channel.addAppsChangedListener(any));

      verifyInOrder([
        database.listApplications(),
        database.persistApps([
          AppsCompanion.insert(
            packageName: "io.sifft.pitchforklauncher",
            name: "FLauncher",
            version: "2.0.0",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          ),
          AppsCompanion.insert(
            packageName: "io.sifft.pitchforklauncher.2",
            name: "FLauncher 2",
            version: "1.0.0",
            banner: Value(null),
            icon: Value(null),
            sideloaded: Value(false),
          )
        ]),
        database.deleteApps(["uninstalled.app"]),
        database.listCategoriesWithVisibleApps(),
        database.listApplications(),
      ]);
    });
  });

  test("passes the package names of apps in a visible category to getApplications", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    List<dynamic>? receivedVisiblePackageNames;
    when(channel.getApplications(any)).thenAnswer((invocation) {
      receivedVisiblePackageNames = invocation.positionalArguments[0] as List<dynamic>;
      return Future.value([]);
    });
    final database = MockFLauncherDatabase();
    when(database.listApplications()).thenAnswer((_) => Future.value([]));
    final category = fakeCategory(name: "Streaming");
    when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value([
          CategoryWithApps(category, [
            fakeApp(packageName: "com.app.one"),
            fakeApp(packageName: "com.app.two"),
          ]),
        ]));
    when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
    when(database.wasCreated).thenReturn(false);

    AppsService(channel, database);
    await untilCalled(channel.addAppsChangedListener(any));
    await untilCalled(channel.getApplications(any));

    expect(receivedVisiblePackageNames, unorderedEquals(["com.app.one", "com.app.two"]));
  });

  test("launchApp calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.launchApp(app);
  });

  test("openAppInfo calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.openAppInfo(app);

    verify(channel.openAppInfo(app.packageName));
  });

  test("uninstallApp calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp();

    await appsService.uninstallApp(app);

    verify(channel.uninstallApp(app.packageName));
  });

  test("openSettings calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    await appsService.openSettings();

    verify(channel.openSettings());
  });

  test("isDefaultLauncher calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    when(channel.isDefaultLauncher()).thenAnswer((_) => Future.value(true));
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    final isDefaultLauncher = await appsService.isDefaultLauncher();

    verify(channel.isDefaultLauncher());
    expect(isDefaultLauncher, isTrue);
  });

  test("startAmbientMode calls channel", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);

    await appsService.startAmbientMode();

    verify(channel.startAmbientMode());
  });

  test("addToCategory adds app to category", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final category = fakeCategory(name: "Category");
    when(database.nextAppCategoryOrder(category.id)).thenAnswer((_) => Future.value(1));

    await appsService.addToCategory(fakeApp(packageName: "app.to.be.added"), category);

    verify(database.insertAppsCategories(
        [AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.to.be.added", order: 1)]));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("addToCategory fetches and persists a banner for an app that doesn't have one yet", () async {
    final channel = MockFLauncherChannel();
    final bannerBytes = Uint8List.fromList([1, 2, 3]);
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    // Must be stubbed after _buildInitialisedAppsService: that helper stubs getAppBanner(any)
    // itself, and a later `when()` call takes priority over an earlier one for the same mock.
    when(channel.getAppBanner("app.without.banner")).thenAnswer((_) => Future.value(bannerBytes));
    final category = fakeCategory(name: "Category");
    when(database.nextAppCategoryOrder(category.id)).thenAnswer((_) => Future.value(0));

    await appsService.addToCategory(fakeApp(packageName: "app.without.banner", banner: null), category);

    verify(channel.getAppBanner("app.without.banner"));
    verify(database.updateApp("app.without.banner", AppsCompanion(banner: Value(bannerBytes))));
  });

  test("addToCategory doesn't fetch a banner for an app that already has one", () async {
    final channel = MockFLauncherChannel();
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final category = fakeCategory(name: "Category");
    when(database.nextAppCategoryOrder(category.id)).thenAnswer((_) => Future.value(0));

    await appsService.addToCategory(
        fakeApp(packageName: "app.with.banner", banner: Uint8List.fromList([1, 2, 3])), category);

    verifyNever(channel.getAppBanner(any));
  });

  test("removeFromCategory removes app from category", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp(packageName: "app.to.be.added");
    final category = fakeCategory(name: "Category");

    await appsService.removeFromCategory(app, category);

    verify(database.deleteAppCategory(category.id, app.packageName));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("moveToCategory adds app to the target category and removes it from the source category", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final app = fakeApp(packageName: "app.to.be.moved");
    final from = fakeCategory(name: "From");
    final to = fakeCategory(name: "To");
    when(database.nextAppCategoryOrder(to.id)).thenAnswer((_) => Future.value(2));

    await appsService.moveToCategory(app, from, to);

    verify(database.insertAppsCategories(
        [AppsCategoriesCompanion.insert(categoryId: to.id, appPackageName: app.packageName, order: 2)]));
    verify(database.deleteAppCategory(from.id, app.packageName));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("saveOrderInCategory persists apps order from memory to database", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")])
    ]);

    await appsService.saveOrderInCategory(category);

    verify(database.replaceAppsCategories([
      AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.1", order: 0),
      AppsCategoriesCompanion.insert(categoryId: category.id, appPackageName: "app.2", order: 1)
    ]));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("reorderApplication changes application order in-memory", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Category");
    final appsService = await _buildInitialisedAppsService(channel, database, [
      CategoryWithApps(category, [fakeApp(packageName: "app.1"), fakeApp(packageName: "app.2")])
    ]);

    appsService.reorderApplication(category, 1, 0);

    expect(appsService.categoriesWithApps[0].applications[0].packageName, "app.2");
    expect(appsService.categoriesWithApps[0].applications[1].packageName, "app.1");
  });

  test("addCategory adds category at index 0 and moves others", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final existingCategory = fakeCategory(name: "Existing Category", order: 0);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(existingCategory, [])],
    );

    await appsService.addCategory("New Category");

    verify(database.insertCategory(CategoriesCompanion.insert(name: "New Category", order: 0)));
    verify(database.updateCategories([CategoriesCompanion(id: Value(existingCategory.id), order: Value(1))]));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("renameCategory renames category", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final category = fakeCategory(name: "Old name", order: 0);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(category, [])],
    );

    await appsService.renameCategory(category, "New name");

    verify(database.updateCategory(category.id, CategoriesCompanion(name: Value("New name"))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("deleteCategory deletes category", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final defaultCategory = fakeCategory(name: "Applications", order: 0);
    final categoryToDelete = fakeCategory(name: "Delete Me", order: 1);
    final appInDefaultCategory = fakeApp();
    final appInCategoryToDelete = fakeApp(packageName: "app.to.be.moved.1");
    final hiddenAppInCategoryToDelete = fakeApp(packageName: "app.to.be.moved.2", hidden: true);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [
        CategoryWithApps(defaultCategory, [appInDefaultCategory]),
        CategoryWithApps(categoryToDelete, [appInCategoryToDelete, hiddenAppInCategoryToDelete])
      ],
    );

    await appsService.deleteCategory(categoryToDelete);

    verify(database.deleteCategory(categoryToDelete.id));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("moveCategory changes categories order", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final applicationsCategory = fakeCategory(name: "Applications", order: 0);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 1);
    final appsService = await _buildInitialisedAppsService(
      channel,
      database,
      [CategoryWithApps(applicationsCategory, []), CategoryWithApps(favoritesCategory, [])],
    );
    when(database.nextAppCategoryOrder(applicationsCategory.id)).thenAnswer((_) => Future.value(1));

    await appsService.moveCategory(1, 0);

    verify(database.updateCategories(
      [
        CategoriesCompanion(id: Value(favoritesCategory.id), order: Value(0)),
        CategoriesCompanion(id: Value(applicationsCategory.id), order: Value(1))
      ],
    ));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("hideApplication hides application", () async {
    final database = MockFLauncherDatabase();
    final application = fakeApp();
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);
    when(database.listApplications()).thenAnswer((_) => Future.value([application]));

    await appsService.hideApplication(application);

    verify(database.updateApp(application.packageName, AppsCompanion(hidden: Value(true))));
    verify(database.listCategoriesWithVisibleApps());
    verify(database.listApplications());
    expect(appsService.applications, [application]);
  });

  test("unHideApplication hides application", () async {
    final database = MockFLauncherDatabase();
    final application = fakeApp();
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.unHideApplication(application);

    verify(database.updateApp(application.packageName, AppsCompanion(hidden: Value(false))));
    verify(database.listCategoriesWithVisibleApps());
    verify(database.listApplications());
  });

  test("setCategoryType persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(type: CategoryType.row);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryType(category, CategoryType.grid);

    verify(database.updateCategory(category.id, CategoriesCompanion(type: Value(CategoryType.grid))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("setCategorySort persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(sort: CategorySort.manual);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategorySort(category, CategorySort.alphabetical);

    verify(database.updateCategory(category.id, CategoriesCompanion(sort: Value(CategorySort.alphabetical))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("setCategoryColumnsCount persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(columnsCount: 6);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryColumnsCount(category, 8);

    verify(database.updateCategory(category.id, CategoriesCompanion(columnsCount: Value(8))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("setCategoryRowHeight persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(rowHeight: 110);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryRowHeight(category, 120);

    verify(database.updateCategory(category.id, CategoriesCompanion(rowHeight: Value(120))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("setCategoryShowName persists change in database", () async {
    final database = MockFLauncherDatabase();
    final category = fakeCategory(showName: true);
    final appsService = await _buildInitialisedAppsService(MockFLauncherChannel(), database, []);

    await appsService.setCategoryShowName(category, false);

    verify(database.updateCategory(category.id, CategoriesCompanion(showName: Value(false))));
    verify(database.listCategoriesWithVisibleApps());
  });

  test("reloadFromDatabase refreshes the cache without re-syncing installed apps", () async {
    final channel = MockFLauncherChannel();
    when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
    final database = MockFLauncherDatabase();
    final appsService = await _buildInitialisedAppsService(channel, database, []);
    final application = fakeApp();
    final category = fakeCategory(name: "Streaming");

    when(database.listApplications()).thenAnswer((_) => Future.value([application]));
    when(database.listCategoriesWithVisibleApps())
        .thenAnswer((_) => Future.value([CategoryWithApps(category, [application])]));

    await appsService.reloadFromDatabase();

    expect(appsService.applications, [application]);
    expect(appsService.categoriesWithApps.length, 1);
    expect(appsService.categoriesWithApps.first.category, category);
    expect(appsService.categoriesWithApps.first.applications, [application]);
    verifyNever(channel.getApplications(any));
  });
}

Future<AppsService> _buildInitialisedAppsService(
  MockFLauncherChannel channel,
  MockFLauncherDatabase database,
  List<CategoryWithApps> categoriesWithApps,
) async {
  when(channel.getApplications(any)).thenAnswer((_) => Future.value([]));
  when(channel.getAppBanner(any)).thenAnswer((_) => Future.value(null));
  when(database.listApplications()).thenAnswer((_) => Future.value([]));
  when(database.listCategoriesWithVisibleApps()).thenAnswer((_) => Future.value(categoriesWithApps));
  when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
  when(database.wasCreated).thenReturn(false);
  final appsService = AppsService(channel, database);
  await untilCalled(channel.addAppsChangedListener(any));
  clearInteractions(channel);
  clearInteractions(database);
  return appsService;
}

class _MockPackageInfoPlatform with MockPlatformInterfaceMixin implements PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async => PackageInfoData(
    appName: "PitchforkLauncher",
    packageName: "io.sifft.pitchforklauncher",
    version: "1.0.0",
    buildNumber: "1",
    buildSignature: "",
  );
}
