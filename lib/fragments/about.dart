import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';

@immutable
class Contributor {
  final String avatar;
  final String name;
  final String link;

  const Contributor({
    required this.avatar,
    required this.name,
    required this.link,
  });
}

class AboutFragment extends StatelessWidget {
  const AboutFragment({super.key});

  _checkUpdate(BuildContext context) async {
    final commonScaffoldState = context.commonScaffoldState;
    if (commonScaffoldState?.mounted != true) return;
    final result = await commonScaffoldState?.loadingRun<UpdateCheckResult>(
      request.checkForUpdate,
      title: appLocalizations.checkUpdate,
    );
    if (result == null) return;
    globalState.appController.handleUpdateCheckResult(
      result: result,
      manual: true,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = context.colorScheme;
    final textTheme = context.textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(settingsCardRadius),
          border: Border.all(
            color: colorScheme.outlineVariant.opacity60,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 58,
                    height: 58,
                  ),
                ),
                const SizedBox(
                  width: 14,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        globalState.packageInfo.version,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              appLocalizations.desc,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            SizedBox(
              height: 42,
              child: FilledButton(
                onPressed: () {
                  _checkUpdate(context);
                },
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(appLocalizations.checkUpdate),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContributorsSection() {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/june2.jpg",
        name: "June2",
        link: "https://t.me/Jibadong",
      ),
      Contributor(
        avatar: "assets/images/avatars/arue.jpg",
        name: "Arue",
        link: "https://t.me/xrcm6868",
      ),
    ];
    return [
      SettingsSection(
        label: appLocalizations.otherContributors,
        dividerIndentWithIcon: true,
        children: [
          for (final contributor in contributors)
            ListItem(
              leading: CircleAvatar(
                radius: 17,
                foregroundImage: AssetImage(contributor.avatar),
              ),
              title: Text(contributor.name),
              subtitle: Text(contributor.link.replaceFirst("https://", "")),
              onTap: () {
                globalState.openUrl(contributor.link);
              },
            ),
        ],
      )
    ];
  }

  List<Widget> _buildMoreSection(BuildContext context) {
    return [
      SettingsSection(
        label: appLocalizations.more,
        dividerIndentWithIcon: true,
        children: [
          ListItem(
            iconData: Icons.telegram,
            title: const Text("Telegram"),
            subtitle: const Text("t.me/FlClash"),
            showArrow: true,
            onTap: () {
              globalState.openUrl(
                "https://t.me/FlClash",
              );
            },
          ),
          ListItem(
            iconData: Icons.code,
            title: Text(appLocalizations.project),
            subtitle: const Text("github.com/Filterrr/FlClash"),
            showArrow: true,
            onTap: () {
              globalState.openUrl(
                "https://github.com/$repository",
              );
            },
          ),
          ListItem(
            iconData: Icons.memory,
            title: Text(appLocalizations.core),
            subtitle: const Text("Clash.Meta · Alpha"),
            showArrow: true,
            onTap: () {
              globalState.openUrl(
                "https://github.com/Filterrr/Clash.Meta/tree/Alpha",
              );
            },
          ),
        ],
      )
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _buildHeader(context),
      ..._buildContributorsSection(),
      ..._buildMoreSection(context),
      const SettingsBottomSpace(),
    ];
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: items.length,
      itemBuilder: (_, index) => items[index],
    );
  }
}
