import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'chip.dart';
import 'list.dart';

class ConnectionItem extends StatefulWidget {
  final Connection connection;
  final Function(String)? onClick;
  final Widget? trailing;

  const ConnectionItem({
    super.key,
    required this.connection,
    this.onClick,
    this.trailing,
  });

  @override
  State<ConnectionItem> createState() => _ConnectionItemState();
}

class _ConnectionItemState extends State<ConnectionItem> {
  Future<ImageProvider?>? _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = _getPackageIcon();
  }

  @override
  void didUpdateWidget(ConnectionItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connection.metadata.process != oldWidget.connection.metadata.process) {
      _iconFuture = _getPackageIcon();
    }
  }

  Future<ImageProvider?> _getPackageIcon() async {
    return await app?.getPackageIcon(widget.connection.metadata.process);
  }

  String _getRequestText(Metadata metadata) {
    var text = "${metadata.network}://";
    final ips = [
      metadata.host,
      metadata.destinationIP,
    ].where((ip) => ip.isNotEmpty);
    text += ips.join("/");
    text += ":${metadata.destinationPort}";
    return text;
  }

  String _getSourceText(Connection connection) {
    final metadata = connection.metadata;
    if (metadata.process.isEmpty) {
      return connection.start.lastUpdateTimeDesc;
    }
    return "${metadata.process} · ${connection.start.lastUpdateTimeDesc}";
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connection;
    if (!Platform.isAndroid) {
      return ListItem(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        tileTitleAlignment: ListTileTitleAlignment.titleHeight,
        title: Text(
          _getRequestText(connection.metadata),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8,
            ),
            Text(
              _getSourceText(connection),
            ),
            const SizedBox(
              height: 8,
            ),
            Wrap(
              runSpacing: 6,
              spacing: 6,
              children: [
                for (final chain in connection.chains)
                  CommonChip(
                    label: chain,
                    onPressed: () {
                      if (widget.onClick == null) return;
                      widget.onClick!(chain);
                    },
                  ),
              ],
            ),
          ],
        ),
        trailing: widget.trailing,
      );
    }
    return Selector<ClashConfig, bool>(
      selector: (_, clashConfig) =>
          clashConfig.findProcessMode == FindProcessMode.always,
      builder: (_, value, child) {
        return ListItem(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          tileTitleAlignment: ListTileTitleAlignment.titleHeight,
          leading: value
              ? GestureDetector(
            onTap: () {
              if (widget.onClick == null) return;
              final process = connection.metadata.process;
              if(process.isEmpty)  return;
              widget.onClick!(process);
            },
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              width: 48,
              height: 48,
              child: FutureBuilder<ImageProvider?>(
                future: _iconFuture,
                builder: (_, snapshot) {
                  if (!snapshot.hasData && snapshot.data == null) {
                    return Container();
                  } else {
                    return Image(
                      image: snapshot.data!,
                      gaplessPlayback: true,
                      width: 48,
                      height: 48,
                    );
                  }
                },
              ),
            ),
          )
              : null,
          title: Text(
            _getRequestText(connection.metadata),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 8,
              ),
              Text(
                _getSourceText(connection),
              ),
              const SizedBox(
                height: 8,
              ),
              Wrap(
                runSpacing: 6,
                spacing: 6,
                children: [
                  for (final chain in connection.chains)
                    CommonChip(
                      label: chain,
                      onPressed: () {
                        if (widget.onClick == null) return;
                        widget.onClick!(chain);
                      },
                    ),
                ],
              ),
            ],
          ),
          trailing: widget.trailing,
        );
      },
    );
  }
}
