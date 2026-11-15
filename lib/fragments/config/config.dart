import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/fragments/config/dns.dart';
import 'package:fl_clash/fragments/config/general.dart';
import 'package:fl_clash/fragments/config/network.dart';
import 'package:fl_clash/fragments/config/sniffer.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ConfigFragment extends StatefulWidget {
  const ConfigFragment({super.key});

  @override
  State<ConfigFragment> createState() => _ConfigFragmentState();
}

class _ConfigFragmentState extends State<ConfigFragment> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 4),
      children: [
        SettingsSection(
          label: appLocalizations.override,
          dividerIndentWithIcon: true,
          children: [
            Selector<ClashConfig, String>(
              selector: (_, clashConfig) => clashConfig.allowLan
                  ? "${clashConfig.mixedPort} · ON"
                  : "${clashConfig.mixedPort} · OFF",
              builder: (_, value, __) {
                return ListItem.open(
                  iconData: Icons.language_outlined,
                  title: Text(appLocalizations.network),
                  subtitle: Text(appLocalizations.networkDesc),
                  valueText: value,
                  delegate: OpenDelegate(
                    title: appLocalizations.network,
                    isScaffold: true,
                    isBlur: false,
                    extendPageWidth: 360,
                    widget: const NetworkListView(),
                  ),
                );
              },
            ),
            Selector<ClashConfig, String>(
              selector: (_, clashConfig) => clashConfig.logLevel.name,
              builder: (_, logLevel, __) {
                return ListItem.open(
                  iconData: Icons.build_outlined,
                  title: Text(appLocalizations.general),
                  subtitle: Text(appLocalizations.generalDesc),
                  valueText: "$logLevel · ${generalItems.length}",
                  delegate: OpenDelegate(
                    title: appLocalizations.general,
                    widget: generateListView(
                      generalGroupedItems(),
                    ),
                    isBlur: false,
                    extendPageWidth: 360,
                  ),
                );
              },
            ),
            Selector<ClashConfig, String>(
              selector: (_, clashConfig) => clashConfig.dns.enhancedMode.name,
              builder: (_, dnsMode, __) {
                return ListItem.open(
                  iconData: Icons.dns_outlined,
                  title: const Text("DNS"),
                  subtitle: Text(appLocalizations.dnsDesc),
                  valueText: dnsMode,
                  delegate: const OpenDelegate(
                    title: "DNS",
                    widget: DnsListView(),
                    isScaffold: true,
                    isBlur: false,
                    extendPageWidth: 360,
                  ),
                );
              },
            ),
            Selector<ClashConfig, bool>(
              selector: (_, clashConfig) => clashConfig.sniffer.enable,
              builder: (_, snifferEnable, __) {
                return ListItem.open(
                  iconData: Icons.travel_explore_outlined,
                  title: Text(appLocalizations.sniffer),
                  subtitle: Text(appLocalizations.snifferDesc),
                  valueText: snifferEnable ? "ON" : "OFF",
                  delegate: const OpenDelegate(
                    title: "Sniffer",
                    widget: SnifferListView(),
                    isScaffold: true,
                    isBlur: false,
                    extendPageWidth: 360,
                  ),
                );
              },
            ),
          ],
        ),
        SettingsNote(
          text: appLocalizations.overrideScopeTip,
        ),
        const SettingsBottomSpace(),
      ],
    );
  }
}
