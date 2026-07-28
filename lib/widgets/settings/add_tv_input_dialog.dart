/*
 * PitchforkLauncher
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

import 'package:flauncher/providers/tv_input/tv_input_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NewTvInput {
  final String label;
  final String profileId;
  final Map<String, String> params;

  const NewTvInput({
    required this.label,
    required this.profileId,
    required this.params,
  });
}

/// Add-input form: a label, a profile picker (populated from [tvInputProfiles], so a new profile
/// shows up here automatically) and, below it, one text field per field the chosen profile
/// declares via [TvInputProfile.paramSpecs].
class AddTvInputDialog extends StatefulWidget {
  @override
  State<AddTvInputDialog> createState() => _AddTvInputDialogState();
}

class _AddTvInputDialogState extends State<AddTvInputDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  late final _labelFocusNode = FocusNode(onKeyEvent: _handleFieldKeyEvent);
  late String _profileId = tvInputProfiles.keys.first;
  final Map<String, TextEditingController> _paramControllers = {};
  final Map<String, FocusNode> _paramFocusNodes = {};

  @override
  void dispose() {
    _labelController.dispose();
    _labelFocusNode.dispose();
    for (final controller in _paramControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _paramFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  TextEditingController _paramController(String key) =>
      _paramControllers.putIfAbsent(key, () => TextEditingController());

  FocusNode _paramFocusNode(String key) => _paramFocusNodes.putIfAbsent(
    key,
    () => FocusNode(onKeyEvent: _handleFieldKeyEvent),
  );

  // Single-line text fields otherwise swallow Up/Down themselves (they're the caret-movement
  // shortcuts for multi-line editing, which these fields never need) instead of letting them
  // bubble up to focus traversal -- claiming them here directly on each field's own FocusNode is
  // what makes D-pad Up/Down move between fields instead of getting stuck. TextInputAction.next
  // (below) additionally makes the on-screen keyboard's own "Next" button do the same forward
  // step while the keyboard is open and owns D-pad input itself.
  KeyEventResult _handleFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      FocusScope.of(context).previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final profile = tvInputProfiles[_profileId]!;
    return SimpleDialog(
      insetPadding: EdgeInsets.only(bottom: 120),
      contentPadding: EdgeInsets.all(24),
      title: Text("Add TV Input"),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                autofocus: true,
                controller: _labelController,
                focusNode: _labelFocusNode,
                decoration: InputDecoration(labelText: "Label"),
                validator: (value) =>
                    value!.trim().isEmpty ? "Must not be empty" : null,
                autovalidateMode: AutovalidateMode.always,
                textCapitalization: TextCapitalization.sentences,
                // TextInputAction.next makes the on-screen keyboard show a "Next" key instead of
                // "Done" -- on Android TV that's how you advance to the next field, since the
                // field's own arrow-key shortcuts are for moving the caret, not for D-pad focus
                // traversal, and the keyboard overlay owns D-pad input while it's open anyway.
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
              ),
              DropdownButtonFormField<String>(
                initialValue: _profileId,
                decoration: InputDecoration(labelText: "TV type"),
                items: [
                  for (final entry in tvInputProfiles.values)
                    DropdownMenuItem(
                      value: entry.id,
                      child: Text(entry.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _profileId = value!),
              ),
              for (final spec in profile.paramSpecs)
                TextFormField(
                  controller: _paramController(spec.key),
                  focusNode: _paramFocusNode(spec.key),
                  decoration: InputDecoration(labelText: spec.label),
                  validator: (value) =>
                      value!.trim().isEmpty ? "Must not be empty" : null,
                  autovalidateMode: AutovalidateMode.always,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                ),
              SizedBox(height: 16),
              TextButton(
                child: Text("Add"),
                onPressed: () {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  Navigator.of(context).pop(
                    NewTvInput(
                      label: _labelController.text.trim(),
                      profileId: _profileId,
                      params: {
                        for (final spec in profile.paramSpecs)
                          spec.key: _paramController(spec.key).text.trim(),
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
