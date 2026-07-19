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

import 'package:flauncher/providers/button_mapping_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  test("loads mappings on construction", () async {
    final fLauncherChannel = MockFLauncherChannel();
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([
          {"keyCode": 190, "label": "KEYCODE_BUTTON_3", "packageName": "com.google.android.youtube.tv"},
        ]));

    final buttonMappingService = ButtonMappingService(fLauncherChannel);
    await untilCalled(fLauncherChannel.getButtonMappings());
    await Future.delayed(Duration.zero);

    expect(buttonMappingService.mappings.length, 1);
    expect(buttonMappingService.mappings.first.keyCode, 190);
    expect(buttonMappingService.mappings.first.label, "KEYCODE_BUTTON_3");
    expect(buttonMappingService.mappings.first.packageName, "com.google.android.youtube.tv");
  });

  test("setMapping persists and refreshes", () async {
    final fLauncherChannel = MockFLauncherChannel();
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([]));
    final buttonMappingService = ButtonMappingService(fLauncherChannel);
    await untilCalled(fLauncherChannel.getButtonMappings());
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([
          {"keyCode": 191, "label": "KEYCODE_BUTTON_4", "packageName": "com.netflix.ninja"},
        ]));

    await buttonMappingService.setMapping(191, "com.netflix.ninja");

    verify(fLauncherChannel.setButtonMapping(191, "com.netflix.ninja"));
    expect(buttonMappingService.mappings.single.packageName, "com.netflix.ninja");
  });

  test("removeMapping removes and refreshes", () async {
    final fLauncherChannel = MockFLauncherChannel();
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([
          {"keyCode": 190, "label": "KEYCODE_BUTTON_3", "packageName": "com.google.android.youtube.tv"},
        ]));
    final buttonMappingService = ButtonMappingService(fLauncherChannel);
    await untilCalled(fLauncherChannel.getButtonMappings());
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([]));

    await buttonMappingService.removeMapping(190);

    verify(fLauncherChannel.removeButtonMapping(190));
    expect(buttonMappingService.mappings, isEmpty);
  });

  test("captureNextButton delegates to the channel", () {
    final fLauncherChannel = MockFLauncherChannel();
    when(fLauncherChannel.getButtonMappings()).thenAnswer((_) => Future.value([]));
    when(fLauncherChannel.captureNextButton()).thenAnswer((_) => Stream.value({"keyCode": 4, "label": "KEYCODE_BACK"}));
    final buttonMappingService = ButtonMappingService(fLauncherChannel);

    expect(buttonMappingService.captureNextButton(), emits({"keyCode": 4, "label": "KEYCODE_BACK"}));
  });
}
