import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class EditProfile extends StatefulWidget {
  final Profile profile;
  final BuildContext context;

  const EditProfile({
    super.key,
    required this.context,
    required this.profile,
  });

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  late TextEditingController labelController;
  late TextEditingController urlController;
  late TextEditingController autoUpdateDurationController;
  late bool autoUpdate;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final fileInfoNotifier = ValueNotifier<FileInfo?>(null);
  Uint8List? fileData;

  @override
  void initState() {
    super.initState();
    labelController = TextEditingController(text: widget.profile.label);
    urlController = TextEditingController(text: widget.profile.url);
    autoUpdate = widget.profile.autoUpdate;
    autoUpdateDurationController = TextEditingController(
      text: widget.profile.autoUpdateDuration.inMinutes.toString(),
    );
    appPath.getProfilePath(widget.profile.id).then((path) async {
      if (path == null) return;
      fileInfoNotifier.value = await _getFileInfo(path);
    });
  }

  _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;
    final config = widget.context.read<Config>();
    var profile = widget.profile.copyWith(
      url: urlController.text,
      label: labelController.text,
      autoUpdate: autoUpdate,
      autoUpdateDuration: Duration(
        minutes: int.parse(
          autoUpdateDurationController.text,
        ),
      ),
    );
    final hasUpdate = widget.profile.url != profile.url;
    if (fileData != null) {
      config.setProfile(await profile.saveFile(fileData!));
    } else {
      config.setProfile(profile);
    }
    if (hasUpdate) {
      globalState.homeScaffoldKey.currentState?.loadingRun(
        () async {
          if (hasUpdate) {
            await globalState.appController.updateProfile(profile);
          }
        },
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  _setAutoUpdate(bool value) {
    if (autoUpdate == value) return;
    setState(() {
      autoUpdate = value;
    });
  }

  Future<FileInfo?> _getFileInfo(path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final lastModified = await file.lastModified();
    final size = await file.length();
    return FileInfo(
      size: size,
      lastModified: lastModified,
    );
  }

  _editProfileFile() async {
    final profilePath = await appPath.getProfilePath(widget.profile.id);
    if (profilePath == null) return;
    globalState.safeRun(() async {
      if (Platform.isAndroid) {
        await app?.openFile(
          profilePath,
        );
        return;
      }
      await launchUrl(
        Uri.file(
          profilePath,
        ),
      );
    });
  }

  _uploadProfileFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile?.bytes == null) return;
    fileData = platformFile?.bytes;
    fileInfoNotifier.value = fileInfoNotifier.value?.copyWith(
      size: fileData?.length ?? 0,
      lastModified: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isUrlProfile = widget.profile.type == ProfileType.url;
    return FloatLayout(
      floatingWidget: FloatWrapper(
        child: FloatingActionButton.extended(
          heroTag: null,
          onPressed: _handleConfirm,
          label: Text(appLocalizations.save),
          icon: const Icon(Icons.save),
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(
            top: 8,
            bottom: 96,
          ),
          children: [
            SettingsSection(
              label: appLocalizations.basicInfo,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: TextFormField(
                    controller: labelController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.name,
                    ),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations.profileNameNullValidationDesc;
                      }
                      return null;
                    },
                  ),
                ),
                if (isUrlProfile)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                    child: TextFormField(
                      controller: urlController,
                      maxLines: 5,
                      minLines: 1,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: appLocalizations.url,
                      ),
                      validator: (String? value) {
                        if (value == null || value.isEmpty) {
                          return appLocalizations.profileUrlNullValidationDesc;
                        }
                        if (!value.isUrl) {
                          return appLocalizations
                              .profileUrlInvalidValidationDesc;
                        }
                        return null;
                      },
                    ),
                  ),
              ],
            ),
            if (isUrlProfile)
              SettingsSection(
                label: appLocalizations.updateSection,
                children: [
                  ListItem.switchItem(
                    isSettings: true,
                    title: Text(appLocalizations.autoUpdate),
                    subtitle: Text(appLocalizations.autoUpdateDesc),
                    delegate: SwitchDelegate<bool>(
                      value: autoUpdate,
                      onChanged: _setAutoUpdate,
                    ),
                  ),
                  if (autoUpdate)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      child: TextFormField(
                        controller: autoUpdateDurationController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: appLocalizations.autoUpdateInterval,
                        ),
                        validator: (String? value) {
                          if (value == null || value.isEmpty) {
                            return appLocalizations
                                .profileAutoUpdateIntervalNullValidationDesc;
                          }
                          try {
                            int.parse(value);
                          } catch (_) {
                            return appLocalizations
                                .profileAutoUpdateIntervalInvalidValidationDesc;
                          }
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ValueListenableBuilder<FileInfo?>(
              valueListenable: fileInfoNotifier,
              builder: (_, fileInfo, __) {
                return FadeBox(
                  child: fileInfo == null
                      ? const SizedBox()
                      : SettingsSection(
                          label: appLocalizations.file,
                          children: [
                            ListItem(
                              isSettings: true,
                              iconData: Icons.description_outlined,
                              title: Text(appLocalizations.profile),
                              subtitle: Text(fileInfo.desc),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: appLocalizations.edit,
                                    onPressed: _editProfileFile,
                                    icon: const Icon(Icons.edit_outlined),
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  IconButton(
                                    tooltip: appLocalizations.upload,
                                    onPressed: _uploadProfileFile,
                                    icon: const Icon(Icons.upload_outlined),
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                );
              },
            ),
            const SettingsBottomSpace(),
          ],
        ),
      ),
    );
  }
}
