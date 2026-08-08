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

import 'dart:async';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/text_shadows.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TimeWidget extends StatefulWidget {
  @override
  State<TimeWidget> createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(Duration(seconds: 1), (_) => _refreshTime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Selector<SettingsService, bool>(
        selector: (_, settingsService) => settingsService.use24HourTimeFormat,
        builder: (context, use24HourTimeFormat, _) => Text(
          use24HourTimeFormat ? DateFormat.Hm().format(_now) : DateFormat.jm().format(_now),
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            fontWeight: FontWeight.bold,
            shadows: kOverlayTextShadows,
          ),
          textAlign: TextAlign.end,
        ),
      );

  void _refreshTime() {
    final now = DateTime.now();
    // Both display formats (Hm/jm, above) show hour:minute only, never seconds -- so a tick that
    // lands in the same minute as the last one wouldn't change what's on screen. Comparing hour
    // and minute (rather than the full DateTime) is also correct across a midnight rollover: the
    // displayed text never shows the date either, so e.g. 00:05 today and 00:05 yesterday really
    // do render identically.
    if (now.hour == _now.hour && now.minute == _now.minute) {
      return;
    }
    setState(() {
      _now = now;
    });
  }
}
