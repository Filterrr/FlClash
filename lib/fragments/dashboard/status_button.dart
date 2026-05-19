import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/network.dart';

class TUNButton extends StatelessWidget {
  const TUNButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      onPressed: () {
        showSheet(
          context: context,
          builder: (_) {
            return generateListView(generateSection(
              items: [
                if (system.isDesktop) const TUNItem(),
                const TunStackItem(),
              ],
            ));
          },
          title: appLocalizations.tun,
        );
      },
      info: Info(
        label: appLocalizations.tun,
        iconData: Icons.stacked_line_chart,
      ),
      child: Container(
        padding: baseInfoEdgeInsets.copyWith(top: 4, bottom: 8, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 1,
              child: TooltipText(
                text: Text(
                  appLocalizations.options,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 12)
                      .toLight,
                ),
              ),
            ),
            Selector<ClashConfig, bool>(
              selector: (_, clashConfig) => clashConfig.tun.enable,
              builder: (_, enable, __) {
                return LocaleBuilder(
                  builder: (_) => Switch(
                    value: enable,
                    onChanged: (value) {
                      final clashConfig = globalState.appController.clashConfig;
                      clashConfig.tun = clashConfig.tun.copyWith(
                        enable: value,
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SystemProxyButton extends StatelessWidget {
  const SystemProxyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      onPressed: () {
        showSheet(
          context: context,
          builder: (_) {
            return generateListView(
              generateSection(
                items: [
                  SystemProxyItem(),
                  BypassDomainItem(),
                ],
              ),
            );
          },
          title: appLocalizations.systemProxy,
        );
      },
      info: Info(
        label: appLocalizations.systemProxy,
        iconData: Icons.shuffle,
      ),
      child: Container(
        padding: baseInfoEdgeInsets.copyWith(top: 4, bottom: 8, right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 1,
              child: TooltipText(
                text: Text(
                  appLocalizations.options,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontSize: 12)
                      .toLight,
                ),
              ),
            ),
            Selector<Config, bool>(
              selector: (_, config) => config.networkProps.systemProxy,
              builder: (_, systemProxy, __) {
                return LocaleBuilder(
                  builder: (_) => Switch(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: systemProxy,
                    onChanged: (value) {
                      final config = globalState.appController.config;
                      config.networkProps =
                          config.networkProps.copyWith(systemProxy: value);
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
