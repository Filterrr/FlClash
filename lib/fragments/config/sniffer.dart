import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SnifferOverrideItem extends StatelessWidget {
  const SnifferOverrideItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<Config, bool>(
      selector: (_, config) => config.overrideSniffer,
      builder: (_, override, __) {
        return ListItem.switchItem(
          title: Text(appLocalizations.overrideSniffer),
          subtitle: Text(appLocalizations.overrideSnifferDesc),
          delegate: SwitchDelegate(
            value: override,
            onChanged: (bool value) async {
              final config = globalState.appController.config;
              config.overrideSniffer = value;
            },
          ),
        );
      },
    );
  }
}

class SnifferEnableItem extends StatelessWidget {
  const SnifferEnableItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, bool>(
      selector: (_, clashConfig) => clashConfig.sniffer.enable,
      builder: (_, enable, __) {
        return ListItem.switchItem(
          title: Text(appLocalizations.status),
          subtitle: Text(appLocalizations.snifferEnableDesc),
          delegate: SwitchDelegate(
            value: enable,
            onChanged: (bool value) async {
              final clashConfig = globalState.appController.clashConfig;
              clashConfig.sniffer = clashConfig.sniffer.copyWith(
                enable: value,
              );
            },
          ),
        );
      },
    );
  }
}

class ForceDnsMappingItem extends StatelessWidget {
  const ForceDnsMappingItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, bool>(
      selector: (_, clashConfig) => clashConfig.sniffer.forceDnsMapping,
      builder: (_, forceDnsMapping, __) {
        return ListItem.switchItem(
          title: Text(appLocalizations.forceDnsMapping),
          subtitle: Text(appLocalizations.forceDnsMappingDesc),
          delegate: SwitchDelegate(
            value: forceDnsMapping,
            onChanged: (bool value) async {
              final clashConfig = globalState.appController.clashConfig;
              clashConfig.sniffer = clashConfig.sniffer.copyWith(
                forceDnsMapping: value,
              );
            },
          ),
        );
      },
    );
  }
}

class ParsePureIpItem extends StatelessWidget {
  const ParsePureIpItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, bool>(
      selector: (_, clashConfig) => clashConfig.sniffer.parsePureIp,
      builder: (_, parsePureIp, __) {
        return ListItem.switchItem(
          title: Text(appLocalizations.parsePureIp),
          subtitle: Text(appLocalizations.parsePureIpDesc),
          delegate: SwitchDelegate(
            value: parsePureIp,
            onChanged: (bool value) async {
              final clashConfig = globalState.appController.clashConfig;
              clashConfig.sniffer = clashConfig.sniffer.copyWith(
                parsePureIp: value,
              );
            },
          ),
        );
      },
    );
  }
}

class OverrideDestinationItem extends StatelessWidget {
  const OverrideDestinationItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, bool>(
      selector: (_, clashConfig) => clashConfig.sniffer.overrideDestination,
      builder: (_, overrideDestination, __) {
        return ListItem.switchItem(
          title: Text(appLocalizations.overrideDestination),
          subtitle: Text(appLocalizations.overrideDestinationDesc),
          delegate: SwitchDelegate(
            value: overrideDestination,
            onChanged: (bool value) async {
              final clashConfig = globalState.appController.clashConfig;
              clashConfig.sniffer = clashConfig.sniffer.copyWith(
                overrideDestination: value,
              );
            },
          ),
        );
      },
    );
  }
}

class SniffHttpPortsItem extends StatelessWidget {
  const SniffHttpPortsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, SniffProtocol>(
      selector: (_, clashConfig) =>
          clashConfig.sniffer.sniff["HTTP"] ?? const SniffProtocol(),
      builder: (_, protocol, __) {
        return ListItem.open(
          title: const Text("HTTP"),
          subtitle: Text(protocol.ports.join(", ")),
          delegate: OpenDelegate(
            isBlur: false,
            title: "HTTP",
            widget: Selector<ClashConfig, List<String>>(
              selector: (_, clashConfig) =>
                  clashConfig.sniffer.sniff["HTTP"]?.ports ?? [],
              shouldRebuild: (prev, next) =>
                  !stringListEquality.equals(prev, next),
              builder: (_, ports, __) {
                return ListPage(
                  title: "HTTP",
                  items: ports,
                  titleBuilder: (item) => Text(item),
                  onChange: (items) {
                    final clashConfig = globalState.appController.clashConfig;
                    final sniff = Map<String, SniffProtocol>.from(
                        clashConfig.sniffer.sniff);
                    sniff["HTTP"] = (sniff["HTTP"] ?? const SniffProtocol())
                        .copyWith(ports: List.from(items));
                    clashConfig.sniffer =
                        clashConfig.sniffer.copyWith(sniff: sniff);
                  },
                );
              },
            ),
            extendPageWidth: 360,
          ),
        );
      },
    );
  }
}

class SniffHttpOverrideDestinationItem extends StatelessWidget {
  const SniffHttpOverrideDestinationItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, bool?>(
      selector: (_, clashConfig) =>
          clashConfig.sniffer.sniff["HTTP"]?.overrideDestination,
      builder: (_, overrideDest, __) {
        return ListItem.switchItem(
          title: Text("${appLocalizations.overrideDestination} (HTTP)"),
          delegate: SwitchDelegate(
            value: overrideDest ?? false,
            onChanged: (bool value) async {
              final clashConfig = globalState.appController.clashConfig;
              final sniff = Map<String, SniffProtocol>.from(
                  clashConfig.sniffer.sniff);
              sniff["HTTP"] = (sniff["HTTP"] ?? const SniffProtocol())
                  .copyWith(overrideDestination: value);
              clashConfig.sniffer =
                  clashConfig.sniffer.copyWith(sniff: sniff);
            },
          ),
        );
      },
    );
  }
}

class SniffTlsPortsItem extends StatelessWidget {
  const SniffTlsPortsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, SniffProtocol>(
      selector: (_, clashConfig) =>
          clashConfig.sniffer.sniff["TLS"] ?? const SniffProtocol(),
      builder: (_, protocol, __) {
        return ListItem.open(
          title: const Text("TLS"),
          subtitle: Text(protocol.ports.join(", ")),
          delegate: OpenDelegate(
            isBlur: false,
            title: "TLS",
            widget: Selector<ClashConfig, List<String>>(
              selector: (_, clashConfig) =>
                  clashConfig.sniffer.sniff["TLS"]?.ports ?? [],
              shouldRebuild: (prev, next) =>
                  !stringListEquality.equals(prev, next),
              builder: (_, ports, __) {
                return ListPage(
                  title: "TLS",
                  items: ports,
                  titleBuilder: (item) => Text(item),
                  onChange: (items) {
                    final clashConfig = globalState.appController.clashConfig;
                    final sniff = Map<String, SniffProtocol>.from(
                        clashConfig.sniffer.sniff);
                    sniff["TLS"] = (sniff["TLS"] ?? const SniffProtocol())
                        .copyWith(ports: List.from(items));
                    clashConfig.sniffer =
                        clashConfig.sniffer.copyWith(sniff: sniff);
                  },
                );
              },
            ),
            extendPageWidth: 360,
          ),
        );
      },
    );
  }
}

class SniffQuicPortsItem extends StatelessWidget {
  const SniffQuicPortsItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClashConfig, SniffProtocol>(
      selector: (_, clashConfig) =>
          clashConfig.sniffer.sniff["QUIC"] ?? const SniffProtocol(),
      builder: (_, protocol, __) {
        return ListItem.open(
          title: const Text("QUIC"),
          subtitle: Text(protocol.ports.join(", ")),
          delegate: OpenDelegate(
            isBlur: false,
            title: "QUIC",
            widget: Selector<ClashConfig, List<String>>(
              selector: (_, clashConfig) =>
                  clashConfig.sniffer.sniff["QUIC"]?.ports ?? [],
              shouldRebuild: (prev, next) =>
                  !stringListEquality.equals(prev, next),
              builder: (_, ports, __) {
                return ListPage(
                  title: "QUIC",
                  items: ports,
                  titleBuilder: (item) => Text(item),
                  onChange: (items) {
                    final clashConfig = globalState.appController.clashConfig;
                    final sniff = Map<String, SniffProtocol>.from(
                        clashConfig.sniffer.sniff);
                    sniff["QUIC"] = (sniff["QUIC"] ?? const SniffProtocol())
                        .copyWith(ports: List.from(items));
                    clashConfig.sniffer =
                        clashConfig.sniffer.copyWith(sniff: sniff);
                  },
                );
              },
            ),
            extendPageWidth: 360,
          ),
        );
      },
    );
  }
}

class ForceDomainItem extends StatelessWidget {
  const ForceDomainItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: Text(appLocalizations.forceDomain),
      subtitle: Text(appLocalizations.forceDomainDesc),
      delegate: OpenDelegate(
        isBlur: false,
        title: appLocalizations.forceDomain,
        widget: Selector<ClashConfig, List<String>>(
          selector: (_, clashConfig) => clashConfig.sniffer.forceDomain,
          shouldRebuild: (prev, next) => !stringListEquality.equals(prev, next),
          builder: (_, forceDomain, __) {
            return ListPage(
              title: appLocalizations.forceDomain,
              items: forceDomain,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                final clashConfig = globalState.appController.clashConfig;
                clashConfig.sniffer = clashConfig.sniffer.copyWith(
                  forceDomain: List.from(items),
                );
              },
            );
          },
        ),
        extendPageWidth: 360,
      ),
    );
  }
}

class SkipDomainItem extends StatelessWidget {
  const SkipDomainItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: Text(appLocalizations.skipDomain),
      subtitle: Text(appLocalizations.skipDomainDesc),
      delegate: OpenDelegate(
        isBlur: false,
        title: appLocalizations.skipDomain,
        widget: Selector<ClashConfig, List<String>>(
          selector: (_, clashConfig) => clashConfig.sniffer.skipDomain,
          shouldRebuild: (prev, next) => !stringListEquality.equals(prev, next),
          builder: (_, skipDomain, __) {
            return ListPage(
              title: appLocalizations.skipDomain,
              items: skipDomain,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                final clashConfig = globalState.appController.clashConfig;
                clashConfig.sniffer = clashConfig.sniffer.copyWith(
                  skipDomain: List.from(items),
                );
              },
            );
          },
        ),
        extendPageWidth: 360,
      ),
    );
  }
}

class SkipSrcAddressItem extends StatelessWidget {
  const SkipSrcAddressItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: Text(appLocalizations.skipSrcAddress),
      subtitle: Text(appLocalizations.skipSrcAddressDesc),
      delegate: OpenDelegate(
        isBlur: false,
        title: appLocalizations.skipSrcAddress,
        widget: Selector<ClashConfig, List<String>>(
          selector: (_, clashConfig) => clashConfig.sniffer.skipSrcAddress,
          shouldRebuild: (prev, next) => !stringListEquality.equals(prev, next),
          builder: (_, skipSrcAddress, __) {
            return ListPage(
              title: appLocalizations.skipSrcAddress,
              items: skipSrcAddress,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                final clashConfig = globalState.appController.clashConfig;
                clashConfig.sniffer = clashConfig.sniffer.copyWith(
                  skipSrcAddress: List.from(items),
                );
              },
            );
          },
        ),
        extendPageWidth: 360,
      ),
    );
  }
}

class SkipDstAddressItem extends StatelessWidget {
  const SkipDstAddressItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem.open(
      title: Text(appLocalizations.skipDstAddress),
      subtitle: Text(appLocalizations.skipDstAddressDesc),
      delegate: OpenDelegate(
        isBlur: false,
        title: appLocalizations.skipDstAddress,
        widget: Selector<ClashConfig, List<String>>(
          selector: (_, clashConfig) => clashConfig.sniffer.skipDstAddress,
          shouldRebuild: (prev, next) => !stringListEquality.equals(prev, next),
          builder: (_, skipDstAddress, __) {
            return ListPage(
              title: appLocalizations.skipDstAddress,
              items: skipDstAddress,
              titleBuilder: (item) => Text(item),
              onChange: (items) {
                final clashConfig = globalState.appController.clashConfig;
                clashConfig.sniffer = clashConfig.sniffer.copyWith(
                  skipDstAddress: List.from(items),
                );
              },
            );
          },
        ),
        extendPageWidth: 360,
      ),
    );
  }
}

class SnifferOptions extends StatelessWidget {
  const SnifferOptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: generateSection(
        title: appLocalizations.options,
        items: [
          const SnifferEnableItem(),
          const ForceDnsMappingItem(),
          const ParsePureIpItem(),
          const OverrideDestinationItem(),
        ],
      ),
    );
  }
}

class SniffProtocolsOptions extends StatelessWidget {
  const SniffProtocolsOptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: generateSection(
        title: appLocalizations.sniffProtocol,
        items: [
          const SniffHttpPortsItem(),
          const SniffHttpOverrideDestinationItem(),
          const SniffTlsPortsItem(),
          const SniffQuicPortsItem(),
        ],
      ),
    );
  }
}

class SnifferFilterOptions extends StatelessWidget {
  const SnifferFilterOptions({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: generateSection(
        title: appLocalizations.filter,
        items: [
          const ForceDomainItem(),
          const SkipDomainItem(),
          const SkipSrcAddressItem(),
          const SkipDstAddressItem(),
        ],
      ),
    );
  }
}

const snifferItems = <Widget>[
  SnifferOverrideItem(),
  SnifferOptions(),
  SniffProtocolsOptions(),
  SnifferFilterOptions(),
];

class SnifferListView extends StatelessWidget {
  const SnifferListView({super.key});

  _initActions(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final commonScaffoldState =
          context.findAncestorStateOfType<CommonScaffoldState>();
      commonScaffoldState?.actions = [
        IconButton(
          onPressed: () {
            globalState.showMessage(
                title: appLocalizations.reset,
                message: TextSpan(
                  text: appLocalizations.resetTip,
                ),
                onTab: () {
                  globalState.appController.clashConfig.sniffer =
                      defaultSniffer;
                  Navigator.of(context).pop();
                });
          },
          tooltip: appLocalizations.reset,
          icon: const Icon(
            Icons.replay,
          ),
        )
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    _initActions(context);
    return generateListView(
      snifferItems,
    );
  }
}
