/*
 * FLauncher
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

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/gradients.dart';
import 'package:flauncher/picsum_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mocks.mocks.dart';

void main() {
  late final _MockPathProviderPlatform pathProviderPlatform;
  setUpAll(() {
    // Needed for rootBundle.load() (used by the default-wallpaper seeding tests) to resolve
    // against the real assets/ bundle.
    TestWidgetsFlutterBinding.ensureInitialized();
    pathProviderPlatform = _MockPathProviderPlatform();
    when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) => Future.value("."));
    PathProviderPlatform.instance = pathProviderPlatform;
  });

  // Every test shares the same fake "." documents directory, so a wallpaper file written by one
  // test would otherwise still exist for the next -- making that next test's WallpaperService
  // construction race its own _init() (which reads the file, plus the Picsum settings) against
  // the test's explicit method calls.
  tearDown(() async {
    final file = File("./wallpaper");
    if (await file.exists()) {
      await file.delete();
    }
  });

  group("pickWallpaper", () {
    test("picks image", () async {
      final pickedFile = _MockXFile();
      when(pickedFile.readAsBytes()).thenAnswer((_) => Future.value(Uint8List.fromList([0x01])));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(imagePicker.pickImage(source: ImageSource.gallery)).thenAnswer((_) => Future.value(pickedFile));
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(true));
      final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, MockUnsplashService(), MockPicsumService(), _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      verify(imagePicker.pickImage(source: ImageSource.gallery));
      verify(settingsService.setUnsplashAuthor(null));
      expect(wallpaperService.wallpaperBytes, [0x01]);
    });

    test("throws error when no file explorer installed", () async {
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(false));
      final wallpaperService = WallpaperService(_MockImagePicker(), fLauncherChannel, MockUnsplashService(), MockPicsumService(), _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      expect(() async => await wallpaperService.pickWallpaper(), throwsA(isInstanceOf<NoFileExplorerException>()));
    });
  });

  test("randomFromUnsplash", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final unsplashService = MockUnsplashService();
    final settingsService = _mockSettingsService();
    final photo = Photo(
      "e07ebff3-0b4d-4e0a-ae94-97ef32bd59e6",
      "John Doe",
      Uri.parse("http://localhost/small.jpg"),
      Uri.parse("http://localhost/raw.jpg"),
      Uri.parse("http://localhost/@author"),
    );
    when(unsplashService.randomPhoto("test")).thenAnswer((_) => Future.value(photo));
    when(unsplashService.downloadPhoto(photo)).thenAnswer((_) => Future.value(Uint8List.fromList([0x01])));
    final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
      ..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.randomFromUnsplash("test");

    verify(unsplashService.randomPhoto("test"));
    verify(settingsService.setUnsplashAuthor('{"username":"John Doe","link":"http://localhost/@author"}'));
    expect(wallpaperService.wallpaperBytes, [0x01]);
  });

  test("randomFromPicsum", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final unsplashService = MockUnsplashService();
    final picsumService = MockPicsumService();
    final settingsService = _mockSettingsService();
    when(picsumService.randomPhoto())
        .thenAnswer((_) => Future.value(PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01]))));
    final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, picsumService, _mockDatabase())
      ..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.randomFromPicsum();

    verify(picsumService.randomPhoto());
    verify(settingsService.setUnsplashAuthor(null));
    verify(settingsService.setPicsumPhotoId(42));
    verify(settingsService.setPicsumGrayscale(false));
    verify(settingsService.setPicsumBlur(null));
    expect(wallpaperService.wallpaperBytes, [0x01]);
    expect(wallpaperService.hasCurrentPicsumPhoto, isTrue);
  });

  group("reapplyPicsumFilters", () {
    test("no-ops when no photo has been fetched yet", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final picsumService = MockPicsumService();
      final settingsService = _mockSettingsService();
      final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, picsumService, _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.reapplyPicsumFilters(grayscale: true);

      verifyNever(picsumService.photoById(any, grayscale: anyNamed("grayscale"), blur: anyNamed("blur")));
      expect(wallpaperService.wallpaperBytes, null);
    });

    test("re-fetches the current photo with grayscale and blur combined, and persists the filters", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final picsumService = MockPicsumService();
      final settingsService = _mockSettingsService();
      when(picsumService.randomPhoto())
          .thenAnswer((_) => Future.value(PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01]))));
      when(picsumService.photoById(42, grayscale: true, blur: 4))
          .thenAnswer((_) => Future.value(Uint8List.fromList([0x02])));
      final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, picsumService, _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      await wallpaperService.randomFromPicsum();

      await wallpaperService.reapplyPicsumFilters(grayscale: true, blur: 4);

      verify(picsumService.photoById(42, grayscale: true, blur: 4));
      verify(settingsService.setPicsumGrayscale(true));
      verify(settingsService.setPicsumBlur(4));
      expect(wallpaperService.wallpaperBytes, [0x02]);
      expect(wallpaperService.picsumGrayscale, isTrue);
      expect(wallpaperService.picsumBlurEnabled, isTrue);
    });
  });

  test("searchFromUnsplash", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final unsplashService = MockUnsplashService();
    final settingsService = _mockSettingsService();
    final photo = Photo(
      "e07ebff3-0b4d-4e0a-ae94-97ef32bd59e6",
      "Username",
      Uri.parse("http://localhost/small.jpg"),
      Uri.parse("http://localhost/raw.jpg"),
      Uri.parse("http://localhost/@author"),
    );
    when(unsplashService.searchPhotos("test")).thenAnswer((_) => Future.value([photo]));
    final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
      ..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    final photos = await wallpaperService.searchFromUnsplash("test");

    expect(photos, [photo]);
  });

  test("setFromUnsplash", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final unsplashService = MockUnsplashService();
    final settingsService = _mockSettingsService();
    final photo = Photo(
      "e07ebff3-0b4d-4e0a-ae94-97ef32bd59e6",
      "John Doe",
      Uri.parse("http://localhost/small.jpg"),
      Uri.parse("http://localhost/raw.jpg"),
      Uri.parse("http://localhost/@author"),
    );
    when(unsplashService.downloadPhoto(photo)).thenAnswer((_) => Future.value(Uint8List.fromList([0x01])));
    final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
      ..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.setFromUnsplash(photo);

    verify(unsplashService.downloadPhoto(photo));
    verify(settingsService.setUnsplashAuthor('{"username":"John Doe","link":"http://localhost/@author"}'));
    verify(settingsService.setPicsumPhotoId(null));
    expect(wallpaperService.wallpaperBytes, [0x01]);
  });

  test("setGradient", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final unsplashService = MockUnsplashService();
    final settingsService = _mockSettingsService();
    final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
      ..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.setGradient(FLauncherGradients.greatWhale);

    verify(settingsService.setGradientUuid(FLauncherGradients.greatWhale.uuid));
    verify(settingsService.setUnsplashAuthor(null));
    verify(settingsService.setPicsumPhotoId(null));
    expect(wallpaperService.wallpaperBytes, null);
  });

  group("seeds default wallpaper", () {
    test("writes bundled asset when fresh install and no wallpaper file exists", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final settingsService = _mockSettingsService();
      final wallpaperService =
          WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase(isFreshInstall: true))
            ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      // isFreshInstall()/rootBundle.load()/file write is a multi-hop async chain -- pump the
      // event queue until it settles rather than guessing a fixed number of ticks.
      await pumpEventQueue();

      expect(wallpaperService.wallpaperBytes, isNotNull);
      expect(wallpaperService.wallpaperBytes, isNotEmpty);
      expect(await File("./wallpaper").exists(), isTrue);
      expect(await File("./wallpaper").readAsBytes(), wallpaperService.wallpaperBytes);
    });

    test("does not seed when not a fresh install", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final settingsService = _mockSettingsService();
      final wallpaperService =
          WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
            ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      await Future.delayed(Duration.zero);

      expect(wallpaperService.wallpaperBytes, isNull);
    });
  });

  group("getGradient", () {
    test("without uuid from settings", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final settingsService = _mockSettingsService();
      when(settingsService.gradientUuid).thenReturn(null);
      final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.greatWhale);
    });

    test("with uuid from settings", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final unsplashService = MockUnsplashService();
      final settingsService = _mockSettingsService();
      when(settingsService.gradientUuid).thenReturn(FLauncherGradients.grassShampoo.uuid);
      final wallpaperService = WallpaperService(imagePicker, fLauncherChannel, unsplashService, MockPicsumService(), _mockDatabase())
        ..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.grassShampoo);
    });
  });
}

/// A [MockFLauncherDatabase] stubbed to report whether this is a fresh install -- gates whether
/// [WallpaperService] seeds the bundled default wallpaper. Defaults to `false` so existing tests
/// (which all assert behavior unrelated to seeding) are unaffected.
MockFLauncherDatabase _mockDatabase({bool isFreshInstall = false}) {
  final database = MockFLauncherDatabase();
  when(database.isFreshInstall()).thenAnswer((_) => Future.value(isFreshInstall));
  return database;
}

/// A [MockSettingsService] with sensible defaults for the Picsum persistence fields, since
/// [WallpaperService]'s constructor kicks off an async `_init()` that reads them if a wallpaper
/// file happens to already exist on disk (these tests all share the same fake "." documents
/// directory, so a file written by an earlier test can still be there for a later one).
MockSettingsService _mockSettingsService() {
  final settingsService = MockSettingsService();
  when(settingsService.picsumPhotoId).thenReturn(null);
  when(settingsService.picsumGrayscale).thenReturn(false);
  when(settingsService.picsumBlur).thenReturn(null);
  when(settingsService.setPicsumPhotoId(any)).thenAnswer((_) => Future.value());
  when(settingsService.setPicsumGrayscale(any)).thenAnswer((_) => Future.value());
  when(settingsService.setPicsumBlur(any)).thenAnswer((_) => Future.value());
  return settingsService;
}

class _MockImagePicker extends Mock implements ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) =>
      super.noSuchMethod(
          Invocation.method(#pickImage, [], {
            #source: source,
            #maxWidth: maxWidth,
            #maxHeight: maxHeight,
            #imageQuality: imageQuality,
            #preferredCameraDevice: preferredCameraDevice,
            #requestFullMetadata: requestFullMetadata,
          }),
          returnValue: Future<XFile?>.value());
}

// ignore: must_be_immutable
class _MockXFile extends Mock implements XFile {
  @override
  Future<Uint8List> readAsBytes() => super
      .noSuchMethod(Invocation.method(#readAsBytes, []), returnValue: Future<Uint8List>.value(Uint8List.fromList([])));
}

class _MockPathProviderPlatform extends Mock with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() =>
      super.noSuchMethod(Invocation.method(#getApplicationDocumentsPath, []), returnValue: Future<String?>.value());
}
