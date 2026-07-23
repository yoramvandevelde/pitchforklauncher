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

import 'dart:convert';
import 'dart:io';

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/picsum_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/unsplash_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier {
  static const _defaultWallpaperAsset = "assets/default_wallpaper.jpg";

  final ImagePicker _imagePicker;
  final FLauncherChannel _fLauncherChannel;
  final UnsplashService _unsplashService;
  final PicsumService _picsumService;
  final FLauncherDatabase _database;
  late SettingsService _settingsService;

  late final File _wallpaperFile;
  Uint8List? _wallpaper;
  int? _currentPicsumPhotoId;
  bool _picsumGrayscale = false;
  int? _picsumBlur;
  int _picsumRequestId = 0;
  int _wallpaperVersion = 0;

  Uint8List? get wallpaperBytes => _wallpaper;

  /// Bumped every time the wallpaper (or gradient) changes. Lets the UI key its background widget
  /// so it can cross-fade between the old and new wallpaper instead of swapping instantly.
  int get wallpaperVersion => _wallpaperVersion;

  /// Whether a Picsum photo has been fetched via [randomFromPicsum] and can be re-filtered via
  /// [reapplyPicsumFilters]. False before the first [randomFromPicsum] call, or after switching to
  /// a different wallpaper source (Gradient, Custom, Unsplash).
  bool get hasCurrentPicsumPhoto => _currentPicsumPhotoId != null;

  /// The filters last applied via [reapplyPicsumFilters] (or reset by [randomFromPicsum]). Lives
  /// here rather than in the control bar's widget state so it survives the bar being closed and
  /// reopened -- otherwise reopening it would show both switches off even though the wallpaper
  /// itself is still filtered.
  bool get picsumGrayscale => _picsumGrayscale;

  bool get picsumBlurEnabled => _picsumBlur != null;

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.greatWhale,
      );

  set settingsService(SettingsService settingsService) => _settingsService = settingsService;

  WallpaperService(
    this._imagePicker,
    this._fLauncherChannel,
    this._unsplashService,
    this._picsumService,
    this._database,
  ) {
    _init();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _wallpaperFile = File("${directory.path}/wallpaper");
    if (await _wallpaperFile.exists()) {
      _wallpaper = await _wallpaperFile.readAsBytes();
      _currentPicsumPhotoId = _settingsService.picsumPhotoId;
      _picsumGrayscale = _settingsService.picsumGrayscale;
      _picsumBlur = _settingsService.picsumBlur;
      notifyListeners();
    } else if (await _database.isFreshInstall()) {
      await _writeWallpaperBytes(await _loadDefaultWallpaperBytes());
      notifyListeners();
    }
  }

  Future<Uint8List> _loadDefaultWallpaperBytes() async =>
      (await rootBundle.load(_defaultWallpaperAsset)).buffer.asUint8List();

  Future<void> _writeWallpaperBytes(Uint8List bytes) async {
    await _wallpaperFile.writeAsBytes(bytes);
    _wallpaper = bytes;
    _wallpaperVersion++;
  }

  /// Shared by every "replace the wallpaper wholesale" path (picked file, Unsplash, the bundled
  /// default): resets Picsum state, writes the new bytes, and records the Unsplash author credit
  /// (or clears it for non-Unsplash sources). Doesn't touch the gradient setting -- it's simply
  /// dormant while a non-null wallpaper is set, same as before this was extracted.
  /// [randomFromPicsum], [reapplyPicsumFilters] and [setGradient] manage their own state instead
  /// of using this, since they need to set (rather than clear) Picsum-specific settings.
  Future<void> _applyWallpaper(Uint8List bytes, {String? unsplashAuthorJson}) async {
    _currentPicsumPhotoId = null;
    _picsumGrayscale = false;
    _picsumBlur = null;
    await _writeWallpaperBytes(bytes);
    await _settingsService.setUnsplashAuthor(unsplashAuthorJson);
    await _clearPicsumSettings();
    notifyListeners();
  }

  /// Explicitly resets the wallpaper back to the bundled default, same image [_init] seeds on a
  /// fresh install -- lets the user return to it later without wiping their data.
  Future<void> resetToDefaultWallpaper() async {
    await _applyWallpaper(await _loadDefaultWallpaperBytes());
  }

  Future<void> pickWallpaper() async {
    if (!await _fLauncherChannel.checkForGetContentAvailability()) {
      throw NoFileExplorerException();
    }
    final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      await _applyWallpaper(await pickedFile.readAsBytes());
    }
  }

  Future<void> randomFromUnsplash(String query) async {
    final photo = await _unsplashService.randomPhoto(query);
    final bytes = await _unsplashService.downloadPhoto(photo);
    await _applyWallpaper(
      bytes,
      unsplashAuthorJson: jsonEncode({"username": photo.username, "link": photo.userLink.toString()}),
    );
  }

  Future<List<Photo>> searchFromUnsplash(String query) => _unsplashService.searchPhotos(query);

  Future<void> randomFromPicsum() async {
    final requestId = ++_picsumRequestId;
    final photo = await _picsumService.randomPhoto();
    if (requestId != _picsumRequestId) {
      return;
    }
    _currentPicsumPhotoId = photo.id;
    _picsumGrayscale = false;
    _picsumBlur = null;
    await _wallpaperFile.writeAsBytes(photo.bytes);
    _wallpaper = photo.bytes;
    _wallpaperVersion++;
    await _settingsService.setUnsplashAuthor(null);
    await _settingsService.setPicsumPhotoId(photo.id);
    await _settingsService.setPicsumGrayscale(false);
    await _settingsService.setPicsumBlur(null);
    notifyListeners();
  }

  /// Re-fetches the current Picsum photo with the given filters, replacing the roll from
  /// [randomFromPicsum] rather than fetching a new random photo. No-ops if called before any
  /// photo was fetched via [randomFromPicsum].
  Future<void> reapplyPicsumFilters({bool grayscale = false, int? blur}) async {
    final id = _currentPicsumPhotoId;
    if (id == null) {
      return;
    }
    final requestId = ++_picsumRequestId;
    final bytes = await _picsumService.photoById(id, grayscale: grayscale, blur: blur);
    if (requestId != _picsumRequestId) {
      return;
    }
    _picsumGrayscale = grayscale;
    _picsumBlur = blur;
    await _wallpaperFile.writeAsBytes(bytes);
    _wallpaper = bytes;
    _wallpaperVersion++;
    await _settingsService.setUnsplashAuthor(null);
    await _settingsService.setPicsumGrayscale(grayscale);
    await _settingsService.setPicsumBlur(blur);
    notifyListeners();
  }

  Future<void> setFromUnsplash(Photo photo) async {
    final bytes = await _unsplashService.downloadPhoto(photo);
    await _applyWallpaper(
      bytes,
      unsplashAuthorJson: jsonEncode({"username": photo.username, "link": photo.userLink.toString()}),
    );
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }
    _currentPicsumPhotoId = null;
    _picsumGrayscale = false;
    _picsumBlur = null;
    _wallpaper = null;
    _wallpaperVersion++;
    await _settingsService.setUnsplashAuthor(null);
    await _settingsService.setGradientUuid(fLauncherGradient.uuid);
    await _clearPicsumSettings();
    notifyListeners();
  }

  Future<void> _clearPicsumSettings() async {
    await _settingsService.setPicsumPhotoId(null);
    await _settingsService.setPicsumGrayscale(false);
    await _settingsService.setPicsumBlur(null);
  }
}

class NoFileExplorerException implements Exception {}
