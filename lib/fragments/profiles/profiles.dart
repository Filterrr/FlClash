import 'dart:ui';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/fragments/config/runtime_config.dart';
import 'package:fl_clash/fragments/profiles/edit_profile.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'add_profile.dart';

enum PopupMenuItemEnum { delete, edit }

enum ProfileActions { edit, update, delete }

class ProfilesFragment extends StatefulWidget {
  const ProfilesFragment({super.key});

  @override
  State<ProfilesFragment> createState() => _ProfilesFragmentState();
}

class _ProfilesFragmentState extends State<ProfilesFragment> {
  Function? applyConfigDebounce;

  _handleShowAddExtendPage() {
    showExtendPage(
      globalState.navigatorKey.currentState!.context,
      body: AddProfile(
        context: globalState.navigatorKey.currentState!.context,
      ),
      title: "${appLocalizations.add}${appLocalizations.profile}",
    );
  }

  _updateProfiles() async {
    final appController = globalState.appController;
    final config = appController.config;
    final profiles = appController.config.profiles;
    final messages = [];
    final updateProfiles = profiles.map<Future>(
      (profile) async {
        if (profile.type == ProfileType.file) return;
        config.setProfile(
          profile.copyWith(isUpdating: true),
        );
        try {
          await appController.updateProfile(profile);
          if (profile.id == appController.config.currentProfile?.id) {
            appController.applyProfileDebounce();
          }
        } catch (e) {
          messages.add("$e\n");
          config.setProfile(
            profile.copyWith(
              isUpdating: false,
            ),
          );
        }
      },
    );
    final titleMedium = context.textTheme.titleMedium;
    await Future.wait(updateProfiles);
    if (messages.isNotEmpty) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(
          children: [
            for (final message in messages)
              TextSpan(text: message, style: titleMedium)
          ],
        ),
      );
    }
  }

  _initScaffold() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted) return;
        final commonScaffoldState =
            context.findAncestorStateOfType<CommonScaffoldState>();
        commonScaffoldState?.actions = [
          IconButton(
            tooltip: appLocalizations.update,
            onPressed: () {
              _updateProfiles();
            },
            icon: const Icon(Icons.sync),
          ),
          const SizedBox(
            width: 8,
          ),
          IconButton(
            tooltip: appLocalizations.profilesSort,
            onPressed: () {
              final profiles = globalState.appController.config.profiles;
              showSheet(
                title: appLocalizations.profilesSort,
                context: context,
                builder: (_) => SizedBox(
                  height: 400,
                  child: ReorderableProfiles(profiles: profiles),
                ),
              );
            },
            icon: const Icon(Icons.sort),
            iconSize: 26,
          ),
        ];
        commonScaffoldState?.floatingActionButton = FloatingActionButton(
          heroTag: null,
          onPressed: _handleShowAddExtendPage,
          child: const Icon(
            Icons.add,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ActiveBuilder(
      label: "profiles",
      builder: (isCurrent, child) {
        if (isCurrent) {
          _initScaffold();
        }
        return child!;
      },
      child: Selector2<AppState, Config, ProfilesSelectorState>(
        selector: (_, appState, config) => ProfilesSelectorState(
          profiles: config.profiles,
          currentProfileId: config.currentProfileId,
          columns: other.getProfilesColumns(appState.viewWidth),
        ),
        builder: (context, state, child) {
          if (state.profiles.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullProfileDesc,
              iconData: Icons.folder_open,
              desc: appLocalizations.profileEmptyDesc,
              action: FilledButton.tonal(
                onPressed: _handleShowAddExtendPage,
                child: Text(
                  "${appLocalizations.add}${appLocalizations.profile}",
                ),
              ),
            );
          }
          final currentIndex = state.profiles.indexWhere(
            (item) => item.id == state.currentProfileId,
          );
          final currentProfile =
              currentIndex == -1 ? null : state.profiles[currentIndex];
          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 88,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentProfile != null)
                    _CurrentProfileSummary(profile: currentProfile),
                  if (currentProfile != null)
                    const SizedBox(
                      height: 4,
                    ),
                  SettingsSectionHeader(
                    label: appLocalizations.profiles,
                    value: "${state.profiles.length}",
                    padding: const EdgeInsets.only(
                      left: 6,
                      right: 6,
                      top: 16,
                      bottom: 7,
                    ),
                  ),
                  Grid(
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    crossAxisCount: state.columns,
                    children: [
                      for (int i = 0; i < state.profiles.length; i++)
                        GridItem(
                          child: ProfileItem(
                            key: Key(state.profiles[i].id),
                            profile: state.profiles[i],
                            groupValue: state.currentProfileId,
                            onChanged: globalState.appController.changeProfile,
                          ),
                        ),
                    ],
                  ),
                  SettingsNote(
                    text: appLocalizations.profileItemTip,
                    padding: const EdgeInsets.only(
                      left: 6,
                      right: 6,
                      top: 8,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 当前配置摘要：订阅名 + 流量进度 + 更新时间。
class _CurrentProfileSummary extends StatelessWidget {
  final Profile profile;

  const _CurrentProfileSummary({required this.profile});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    final subscriptionInfo = profile.subscriptionInfo;
    final traffic = subscriptionInfo != null && subscriptionInfo.total > 0
        ? subscriptionInfo
        : null;
    return Padding(
      padding: const EdgeInsets.only(
        top: 4,
        bottom: 4,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(settingsCardRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.opacity60,
          ),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer.opacity60,
              colorScheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(
                  width: 7,
                ),
                Text(
                  appLocalizations.currentProfile,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.opacity12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    profile.type == ProfileType.url
                        ? appLocalizations.url
                        : appLocalizations.file,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 9,
            ),
            Text(
              profile.label ?? profile.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (traffic != null) ...[
              const SizedBox(
                height: 10,
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: (traffic.upload + traffic.download) / traffic.total,
                  backgroundColor: colorScheme.primary.opacity12,
                ),
              ),
              const SizedBox(
                height: 7,
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${TrafficValue(value: traffic.upload + traffic.download).show} / "
                      "${TrafficValue(value: traffic.total).show}",
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (traffic.expire != 0)
                    Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        traffic.expire * 1000,
                      ).show,
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(
              height: 9,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.lastUpdateDate?.lastUpdateTimeDesc ??
                        appLocalizations.noInfo,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ),
                if (profile.realAutoUpdate)
                  Text(
                    "${appLocalizations.autoUpdate} · ${profile.autoUpdateDuration.inMinutes} ${appLocalizations.minutes}",
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileItem extends StatelessWidget {
  final Profile profile;
  final String? groupValue;
  final void Function(String? value) onChanged;

  const ProfileItem({
    super.key,
    required this.profile,
    required this.groupValue,
    required this.onChanged,
  });

  _handleDeleteProfile(BuildContext context) async {
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(
        text: appLocalizations.deleteProfileTip,
      ),
      onTab: () async {
        await globalState.appController.deleteProfile(profile.id);
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  _handleUpdateProfile() async {
    await globalState.safeRun<void>(updateProfile);
  }

  Future updateProfile() async {
    final appController = globalState.appController;
    final config = appController.config;
    if (profile.type == ProfileType.file) return;
    await globalState.safeRun(() async {
      try {
        config.setProfile(
          profile.copyWith(
            isUpdating: true,
          ),
        );
        await appController.updateProfile(profile);
        if (profile.id == appController.config.currentProfile?.id) {
          appController.applyProfileDebounce();
        }
      } catch (e) {
        config.setProfile(
          profile.copyWith(
            isUpdating: false,
          ),
        );
        rethrow;
      }
    });
  }

  _handleShowEditExtendPage(BuildContext context) {
    showExtendPage(
      context,
      body: EditProfile(
        profile: profile,
        context: context,
      ),
      title: "${appLocalizations.edit}${appLocalizations.profile}",
    );
  }

  _handleShowRuntimeConfig(BuildContext context) {
    showExtendPage(
      context,
      body: RuntimeConfigFragment(profile: profile),
      title: appLocalizations.runtimeConfig,
      isScaffold: true,
      isBlur: false,
    );
  }

  String _buildSubtitle() {
    final lastUpdate = profile.lastUpdateDate?.lastUpdateTimeDesc;
    final source = profile.type == ProfileType.url ? profile.url : null;
    if (source == null || source.isEmpty) {
      return lastUpdate ?? appLocalizations.noInfo;
    }
    final host = Uri.tryParse(source)?.host ?? source;
    return host.isEmpty
        ? (lastUpdate ?? appLocalizations.noInfo)
        : (lastUpdate == null ? host : "$host · $lastUpdate");
  }

  Widget? _buildTrafficLine(BuildContext context) {
    final subscriptionInfo = profile.subscriptionInfo;
    if (subscriptionInfo == null || subscriptionInfo.total <= 0) {
      return null;
    }
    final use = subscriptionInfo.upload + subscriptionInfo.download;
    final total = subscriptionInfo.total;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          minHeight: 5,
          value: use / total,
          backgroundColor: context.colorScheme.primary.opacity12,
        ),
      ),
    );
  }

  Widget? _buildTrafficDesc(BuildContext context) {
    final subscriptionInfo = profile.subscriptionInfo;
    if (subscriptionInfo == null || subscriptionInfo.total <= 0) {
      return null;
    }
    final use = subscriptionInfo.upload + subscriptionInfo.download;
    return Text(
      "${TrafficValue(value: use).show} / ${TrafficValue(value: subscriptionInfo.total).show}",
      style: context.textTheme.labelSmall?.copyWith(
        color: context.colorScheme.outline,
      ),
    );
  }

  Widget _buildBadge(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isCurrent = profile.id == groupValue;
    if (!isCurrent && profile.isUpdating) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrent
            ? colorScheme.primary.opacity12
            : colorScheme.surfaceContainerHighest.opacity60,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isCurrent
            ? appLocalizations.currentProfile
            : (profile.type == ProfileType.url
                ? appLocalizations.url
                : appLocalizations.file),
        style: context.textTheme.labelSmall?.copyWith(
          color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final isCurrent = profile.id == groupValue;
    return Material(
      color: isCurrent
          ? colorScheme.primaryContainer.opacity60
          : colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(settingsCardRadius),
        side: BorderSide(
          color: isCurrent
              ? colorScheme.primary.opacity60
              : colorScheme.outlineVariant.opacity60,
          width: isCurrent ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          onChanged(profile.id);
        },
        onLongPress: () => _handleShowRuntimeConfig(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SettingsIconTile(
                      iconData: profile.type == ProfileType.url
                          ? Icons.cloud_outlined
                          : Icons.description_outlined,
                    ),
                  ),
                  const SizedBox(
                    width: 11,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.label ?? profile.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(
                          height: 3,
                        ),
                        Text(
                          _buildSubtitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 6,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SizedBox(
                      height: 22,
                      child: Center(child: _buildBadge(context)),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: FadeBox(
                      child: profile.isUpdating
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : CommonPopupMenu<ProfileActions>(
                              items: [
                                CommonPopupMenuItem(
                                  action: ProfileActions.edit,
                                  label: appLocalizations.edit,
                                  iconData: Icons.edit,
                                ),
                                if (profile.type == ProfileType.url)
                                  CommonPopupMenuItem(
                                    action: ProfileActions.update,
                                    label: appLocalizations.update,
                                    iconData: Icons.sync,
                                  ),
                                CommonPopupMenuItem(
                                  action: ProfileActions.delete,
                                  label: appLocalizations.delete,
                                  iconData: Icons.delete,
                                ),
                              ],
                              onSelected: (ProfileActions? action) async {
                                switch (action) {
                                  case ProfileActions.edit:
                                    _handleShowEditExtendPage(context);
                                    break;
                                  case ProfileActions.delete:
                                    _handleDeleteProfile(context);
                                    break;
                                  case ProfileActions.update:
                                    _handleUpdateProfile();
                                    break;
                                  case null:
                                    break;
                                }
                              },
                            ),
                    ),
                  ),
                ],
              ),
              if (_buildTrafficDesc(context) != null) ...[
                _buildTrafficLine(context)!,
                const SizedBox(
                  height: 4,
                ),
                _buildTrafficDesc(context)!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ReorderableProfiles extends StatefulWidget {
  final List<Profile> profiles;

  const ReorderableProfiles({
    super.key,
    required this.profiles,
  });

  @override
  State<ReorderableProfiles> createState() => _ReorderableProfilesState();
}

class _ReorderableProfilesState extends State<ReorderableProfiles> {
  late List<Profile> profiles;

  @override
  void initState() {
    super.initState();
    profiles = List.from(widget.profiles);
  }

  Widget proxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    final profile = profiles[index];
    return AnimatedBuilder(
      animation: animation,
      builder: (_, Widget? child) {
        final double animValue = Curves.easeInOut.transform(animation.value);
        final double scale = lerpDouble(1, 1.02, animValue)!;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        key: Key(profile.id),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _buildRow(profile, index, isProxy: true),
      ),
    );
  }

  Widget _buildRow(
    Profile profile,
    int index, {
    bool isProxy = false,
  }) {
    final colorScheme = context.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.opacity60,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        child: Row(
          children: [
            SettingsIconTile(
              iconData: profile.type == ProfileType.url
                  ? Icons.cloud_outlined
                  : Icons.description_outlined,
              isNeutral: true,
            ),
            const SizedBox(
              width: 11,
            ),
            Expanded(
              child: Text(
                profile.label ?? profile.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!isProxy)
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  color: colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          flex: 1,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            proxyDecorator: proxyDecorator,
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final profile = profiles.removeAt(oldIndex);
                profiles.insert(newIndex, profile);
              });
            },
            itemBuilder: (_, index) {
              return Container(
                key: Key(profiles[index].id),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildRow(profiles[index], index),
              );
            },
            itemCount: profiles.length,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 24,
          ),
          child: FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              globalState.appController.config.profiles = profiles;
            },
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  appLocalizations.confirm,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
