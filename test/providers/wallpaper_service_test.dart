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
import 'dart:ui';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/app_log.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/picsum_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
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
    when(
      pathProviderPlatform.getApplicationDocumentsPath(),
    ).thenAnswer((_) => Future.value("."));
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
      when(
        pickedFile.readAsBytes(),
      ).thenAnswer((_) => Future.value(Uint8List.fromList([0x01])));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(
        imagePicker.pickImage(source: ImageSource.gallery),
      ).thenAnswer((_) => Future.value(pickedFile));
      when(
        fLauncherChannel.checkForGetContentAvailability(),
      ).thenAnswer((_) => Future.value(true));
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      verify(imagePicker.pickImage(source: ImageSource.gallery));
      // [0x01] isn't valid image data, so this also exercises _resizeToScreen's decode-failure
      // fallback: the bytes are stored as-is instead of the pick blowing up.
      expect(wallpaperService.wallpaperBytes, [0x01]);
    });

    test("resizes a picked image bigger than the screen", () async {
      final pickedBytes = await _solidColorImageBytes(400, 300);
      final pickedFile = _MockXFile();
      when(
        pickedFile.readAsBytes(),
      ).thenAnswer((_) => Future.value(pickedBytes));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(
        imagePicker.pickImage(source: ImageSource.gallery),
      ).thenAnswer((_) => Future.value(pickedFile));
      when(
        fLauncherChannel.checkForGetContentAvailability(),
      ).thenAnswer((_) => Future.value(true));
      const targetSize = Size(100, 50);
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
        targetWallpaperSize: () => targetSize,
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      final codec = await instantiateImageCodec(wallpaperService.wallpaperBytes!);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, targetSize.width.round());
      expect(image.height, targetSize.height.round());
    });

    test("leaves a picked image unchanged when it already fits the screen", () async {
      final pickedBytes = await _solidColorImageBytes(50, 25);
      final pickedFile = _MockXFile();
      when(
        pickedFile.readAsBytes(),
      ).thenAnswer((_) => Future.value(pickedBytes));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(
        imagePicker.pickImage(source: ImageSource.gallery),
      ).thenAnswer((_) => Future.value(pickedFile));
      when(
        fLauncherChannel.checkForGetContentAvailability(),
      ).thenAnswer((_) => Future.value(true));
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
        targetWallpaperSize: () => const Size(200, 100),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      expect(wallpaperService.wallpaperBytes, pickedBytes);
    });

    test("throws error when no file explorer installed", () async {
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(
        fLauncherChannel.checkForGetContentAvailability(),
      ).thenAnswer((_) => Future.value(false));
      final wallpaperService = WallpaperService(
        _MockImagePicker(),
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      expect(
        () async => await wallpaperService.pickWallpaper(),
        throwsA(isInstanceOf<NoFileExplorerException>()),
      );
    });
  });

  test("randomFromPicsum", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final picsumService = MockPicsumService();
    final settingsService = _mockSettingsService();
    when(picsumService.randomPhoto()).thenAnswer(
      (_) =>
          Future.value(PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01]))),
    );
    final wallpaperService = WallpaperService(
      imagePicker,
      fLauncherChannel,
      picsumService,
      _mockDatabase(),
    )..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.randomFromPicsum();

    verify(picsumService.randomPhoto());
    verify(settingsService.setPicsumPhotoId(42));
    verify(settingsService.setPicsumGrayscale(false));
    verify(settingsService.setPicsumBlur(null));
    expect(wallpaperService.wallpaperBytes, [0x01]);
    expect(wallpaperService.hasCurrentPicsumPhoto, isTrue);
  });

  test("randomFromPicsum logs to AppLog and rethrows on failure", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final picsumService = MockPicsumService();
    final settingsService = _mockSettingsService();
    when(picsumService.randomPhoto()).thenThrow(PicsumException("boom"));
    final wallpaperService = WallpaperService(
      imagePicker,
      fLauncherChannel,
      picsumService,
      _mockDatabase(),
    )..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await expectLater(
      () => wallpaperService.randomFromPicsum(),
      throwsA(isInstanceOf<PicsumException>()),
    );

    final entries = AppLog.instance.entries;
    expect(entries, isNotEmpty);
    expect(entries.first.source, "Picsum");
    expect(entries.first.message, contains("boom"));
  });

  group("reapplyPicsumFilters", () {
    test("no-ops when no photo has been fetched yet", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final picsumService = MockPicsumService();
      final settingsService = _mockSettingsService();
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        picsumService,
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.reapplyPicsumFilters(grayscale: true);

      verifyNever(
        picsumService.photoById(
          any,
          grayscale: anyNamed("grayscale"),
          blur: anyNamed("blur"),
        ),
      );
      expect(wallpaperService.wallpaperBytes, null);
    });

    test(
      "re-fetches the current photo with grayscale and blur combined, and persists the filters",
      () async {
        final imagePicker = _MockImagePicker();
        final fLauncherChannel = MockFLauncherChannel();
        final picsumService = MockPicsumService();
        final settingsService = _mockSettingsService();
        when(picsumService.randomPhoto()).thenAnswer(
          (_) => Future.value(
            PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01])),
          ),
        );
        when(
          picsumService.photoById(42, grayscale: true, blur: 4),
        ).thenAnswer((_) => Future.value(Uint8List.fromList([0x02])));
        final wallpaperService = WallpaperService(
          imagePicker,
          fLauncherChannel,
          picsumService,
          _mockDatabase(),
        )..settingsService = settingsService;
        await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
        await wallpaperService.randomFromPicsum();

        await wallpaperService.reapplyPicsumFilters(grayscale: true, blur: 4);

        verify(picsumService.photoById(42, grayscale: true, blur: 4));
        verify(settingsService.setPicsumGrayscale(true));
        verify(settingsService.setPicsumBlur(4));
        expect(wallpaperService.wallpaperBytes, [0x02]);
        expect(wallpaperService.picsumGrayscale, isTrue);
        expect(wallpaperService.picsumBlurEnabled, isTrue);
      },
    );

    test("logs to AppLog and rethrows on failure", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final picsumService = MockPicsumService();
      final settingsService = _mockSettingsService();
      when(picsumService.randomPhoto()).thenAnswer(
        (_) => Future.value(
          PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01])),
        ),
      );
      when(
        picsumService.photoById(42, grayscale: true, blur: anyNamed("blur")),
      ).thenThrow(PicsumException("boom"));
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        picsumService,
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      await wallpaperService.randomFromPicsum();

      await expectLater(
        () => wallpaperService.reapplyPicsumFilters(grayscale: true),
        throwsA(isInstanceOf<PicsumException>()),
      );

      final entries = AppLog.instance.entries;
      expect(entries, isNotEmpty);
      expect(entries.first.source, "Picsum");
      expect(entries.first.message, contains("boom"));
    });
  });

  test("setGradient", () async {
    final imagePicker = _MockImagePicker();
    final fLauncherChannel = MockFLauncherChannel();
    final settingsService = _mockSettingsService();
    final wallpaperService = WallpaperService(
      imagePicker,
      fLauncherChannel,
      MockPicsumService(),
      _mockDatabase(),
    )..settingsService = settingsService;
    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

    await wallpaperService.setGradient(FLauncherGradients.greatWhale);

    verify(settingsService.setGradientUuid(FLauncherGradients.greatWhale.uuid));
    verify(settingsService.setPicsumPhotoId(null));
    expect(wallpaperService.wallpaperBytes, null);
  });

  test(
    "resetToDefaultWallpaper writes the bundled asset and clears other sources' state",
    () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.resetToDefaultWallpaper();

      verify(settingsService.setPicsumPhotoId(null));
      verify(settingsService.setPicsumGrayscale(false));
      verify(settingsService.setPicsumBlur(null));
      expect(wallpaperService.wallpaperBytes, isNotNull);
      expect(wallpaperService.wallpaperBytes, isNotEmpty);
      expect(wallpaperService.hasCurrentPicsumPhoto, isFalse);
    },
  );

  group("seeds default wallpaper", () {
    test(
      "writes bundled asset when fresh install and no wallpaper file exists",
      () async {
        final imagePicker = _MockImagePicker();
        final fLauncherChannel = MockFLauncherChannel();
        final settingsService = _mockSettingsService();
        final wallpaperService = WallpaperService(
          imagePicker,
          fLauncherChannel,
          MockPicsumService(),
          _mockDatabase(isFreshInstall: true),
          // Disabled so this test can assert byte-for-byte fidelity below -- resizing is covered
          // separately in "resizes the seeded default wallpaper to the target screen size".
          targetWallpaperSize: () => null,
        )..settingsService = settingsService;
        await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
        // isFreshInstall()/rootBundle.load()/file write is a multi-hop async chain that now
        // includes a real (multi-MB) disk read/write, so pumpEventQueue() -- which only drains
        // already-queued microtasks a fixed number of times rather than letting wall-clock time
        // pass -- can exit before the write actually finishes. Poll for the real completion signal
        // instead, bounded by a generous timeout.
        final stopwatch = Stopwatch()..start();
        while (wallpaperService.wallpaperBytes == null &&
            stopwatch.elapsed < const Duration(seconds: 10)) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        expect(wallpaperService.wallpaperBytes, isNotNull);
        expect(wallpaperService.wallpaperBytes, isNotEmpty);
        expect(await File("./wallpaper").exists(), isTrue);
        expect(
          await File("./wallpaper").readAsBytes(),
          wallpaperService.wallpaperBytes,
        );
        // Not just non-empty: byte-for-byte identical to the actual bundled asset. A regression
        // to `.buffer.asUint8List()` (which ignores a ByteData's offsetInBytes/lengthInBytes and
        // can return a view into a different/larger buffer instead of the loaded asset's own
        // bytes) would still pass the two checks above while silently seeding garbage.
        expect(
          wallpaperService.wallpaperBytes,
          await File("assets/default_wallpaper.jpg").readAsBytes(),
        );
      },
    );

    test(
      "resizes the seeded default wallpaper to the target screen size",
      () async {
        final imagePicker = _MockImagePicker();
        final fLauncherChannel = MockFLauncherChannel();
        final settingsService = _mockSettingsService();
        // assets/default_wallpaper.jpg is 4000x2491 -- comfortably bigger than this target on
        // both axes, so a resize is guaranteed to actually trigger.
        const targetSize = Size(200, 100);
        final wallpaperService = WallpaperService(
          imagePicker,
          fLauncherChannel,
          MockPicsumService(),
          _mockDatabase(isFreshInstall: true),
          targetWallpaperSize: () => targetSize,
        )..settingsService = settingsService;
        await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
        final stopwatch = Stopwatch()..start();
        while (wallpaperService.wallpaperBytes == null &&
            stopwatch.elapsed < const Duration(seconds: 10)) {
          await Future.delayed(const Duration(milliseconds: 10));
        }

        final bytes = wallpaperService.wallpaperBytes!;
        // Resized output is re-encoded (PNG), so it's a different byte sequence from the
        // original JPEG asset -- proves the bytes on disk were actually transformed, not just
        // passed through unchanged.
        expect(bytes, isNot(await File("assets/default_wallpaper.jpg").readAsBytes()));
        final codec = await instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, targetSize.width.round());
        expect(image.height, targetSize.height.round());
      },
    );

    test("does not seed when not a fresh install", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      await Future.delayed(Duration.zero);

      expect(wallpaperService.wallpaperBytes, isNull);
    });
  });

  group("getGradient", () {
    test("without uuid from settings", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(settingsService.gradientUuid).thenReturn(null);
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.greatWhale);
    });

    test("with uuid from settings", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = _mockSettingsService();
      when(
        settingsService.gradientUuid,
      ).thenReturn(FLauncherGradients.grassShampoo.uuid);
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        MockPicsumService(),
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient, FLauncherGradients.grassShampoo);
    });
  });

  group("restoreWallpaper", () {
    test("preserves Picsum state when restoring bytes", () async {
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final picsumService = MockPicsumService();
      final settingsService = _mockSettingsService();
      when(picsumService.randomPhoto()).thenAnswer(
        (_) => Future.value(
          PicsumPhoto(id: 42, bytes: Uint8List.fromList([0x01])),
        ),
      );
      final wallpaperService = WallpaperService(
        imagePicker,
        fLauncherChannel,
        picsumService,
        _mockDatabase(),
      )..settingsService = settingsService;
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.randomFromPicsum();
      expect(wallpaperService.hasCurrentPicsumPhoto, isTrue);

      // Simulate the settings having been restored from a backup already.
      when(settingsService.picsumPhotoId).thenReturn(42);
      when(settingsService.picsumGrayscale).thenReturn(true);
      when(settingsService.picsumBlur).thenReturn(5);

      await wallpaperService.restoreWallpaper(Uint8List.fromList([0x02]));

      expect(wallpaperService.wallpaperBytes, [0x02]);
      expect(wallpaperService.hasCurrentPicsumPhoto, isTrue);
    });
  });
}

/// A tiny solid-color image, real enough to decode via [instantiateImageCodec] -- used to exercise
/// [WallpaperService]'s resize path without a binary fixture file on disk.
Future<Uint8List> _solidColorImageBytes(int width, int height) async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final byteData = await image.toByteData(format: ImageByteFormat.png);
  return Uint8List.sublistView(byteData!);
}

/// A [MockFLauncherDatabase] stubbed to report whether this is a fresh install -- gates whether
/// [WallpaperService] seeds the bundled default wallpaper. Defaults to `false` so existing tests
/// (which all assert behavior unrelated to seeding) are unaffected.
MockFLauncherDatabase _mockDatabase({bool isFreshInstall = false}) {
  final database = MockFLauncherDatabase();
  when(
    database.isFreshInstall(),
  ).thenAnswer((_) => Future.value(isFreshInstall));
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
  when(
    settingsService.setPicsumGrayscale(any),
  ).thenAnswer((_) => Future.value());
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
  }) => super.noSuchMethod(
    Invocation.method(#pickImage, [], {
      #source: source,
      #maxWidth: maxWidth,
      #maxHeight: maxHeight,
      #imageQuality: imageQuality,
      #preferredCameraDevice: preferredCameraDevice,
      #requestFullMetadata: requestFullMetadata,
    }),
    returnValue: Future<XFile?>.value(),
  );
}

// ignore: must_be_immutable
class _MockXFile extends Mock implements XFile {
  @override
  Future<Uint8List> readAsBytes() => super.noSuchMethod(
    Invocation.method(#readAsBytes, []),
    returnValue: Future<Uint8List>.value(Uint8List.fromList([])),
  );
}

class _MockPathProviderPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() => super.noSuchMethod(
    Invocation.method(#getApplicationDocumentsPath, []),
    returnValue: Future<String?>.value(),
  );
}
