import 'package:fl_clash/clash/clash.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AndroidManager extends StatefulWidget {
  final Widget child;

  const AndroidManager({
    super.key,
    required this.child,
  });

  @override
  State<AndroidManager> createState() => _AndroidContainerState();
}

class _AndroidContainerState extends State<AndroidManager> {
  bool _hasRequestedBatteryOptimization = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Widget _updateCoreState(Widget child) {
    return Selector2<Config, ClashConfig, CoreState>(
      selector: (_, config, clashConfig) => CoreState(
        enable: config.vpnProps.enable,
        accessControl: config.isAccessControl ? config.accessControl : null,
        ipv6: clashConfig.ipv6,
        allowBypass: config.vpnProps.allowBypass,
        bypassDomain: config.networkProps.bypassDomain,
        systemProxy: config.vpnProps.systemProxy,
        onlyProxy: config.appSetting.onlyProxy,
        currentProfileName:
            config.currentProfile?.label ?? config.currentProfileId ?? "",
        routeAddress: clashConfig.routeAddress,
        disableIcmpForwarding: clashConfig.tun.disableIcmpForwarding,
      ),
      builder: (__, state, child) {
        clashLib?.setState(state);
        if (state.enable && !_hasRequestedBatteryOptimization) {
          _hasRequestedBatteryOptimization = true;
          _requestBatteryOptimization();
        }
        return child!;
      },
      child: child,
    );
  }

  void _requestBatteryOptimization() async {
    final isIgnoring = await app?.isIgnoringBatteryOptimizations() ?? false;
    if (!isIgnoring) {
      app?.requestIgnoreBatteryOptimizations();
    }
  }

  Widget _excludeContainer(Widget child) {
    return Selector<Config, bool>(
      selector: (_, config) => config.appSetting.hidden,
      builder: (_, hidden, child) {
        app?.updateExcludeFromRecents(hidden);
        return child!;
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _updateCoreState(
      _excludeContainer(
        widget.child,
      ),
    );
  }
}
