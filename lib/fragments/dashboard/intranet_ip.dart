import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class IntranetIP extends StatefulWidget {
  const IntranetIP({super.key});

  @override
  State<IntranetIP> createState() => _IntranetIPState();
}

class _IntranetIPState extends State<IntranetIP> {
  final ipNotifier = ValueNotifier<String?>("");
  late StreamSubscription subscription;

  Future<String?> getLocalIpAddress() async {
    await Future.delayed(animateDuration);
    List<NetworkInterface> interfaces = await NetworkInterface.list(
      includeLoopback: false,
    )
      ..sort((a, b) {
        if (a.isWifi && !b.isWifi) return -1;
        if (!a.isWifi && b.isWifi) return 1;
        if (a.includesIPv4 && !b.includesIPv4) return -1;
        if (!a.includesIPv4 && b.includesIPv4) return 1;
        return 0;
      });
    for (final interface in interfaces) {
      final addresses = interface.addresses;
      if (addresses.isEmpty) {
        continue;
      }
      addresses.sort((a, b) {
        if (a.isIPv4 && !b.isIPv4) return -1;
        if (!a.isIPv4 && b.isIPv4) return 1;
        return 0;
      });
      return addresses.first.address;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    subscription = Connectivity().onConnectivityChanged.listen((_) async {
      ipNotifier.value = null;
      ipNotifier.value = await getLocalIpAddress() ?? "";
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ipNotifier.value = await getLocalIpAddress() ?? "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      info: Info(
        label: appLocalizations.intranetIP,
        iconData: Icons.devices,
      ),
      onPressed: () {},
      child: Container(
        padding: baseInfoEdgeInsets.copyWith(top: 0),
        child: SizedBox(
          height: globalState.measure.bodyMediumHeight + 2,
          child: ValueListenableBuilder(
            valueListenable: ipNotifier,
            builder: (_, value, __) {
              return FadeThroughBox(
                child: value != null
                    ? TooltipText(
                        text: Text(
                          value.isNotEmpty
                              ? value
                              : appLocalizations.noNetwork,
                          style: context.textTheme.bodyMedium?.toLight,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(2),
                        child: const AspectRatio(
                          aspectRatio: 1,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    subscription.cancel();
    ipNotifier.dispose();
  }
}
