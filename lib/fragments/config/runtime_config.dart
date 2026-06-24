import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

class RuntimeConfigFragment extends StatefulWidget {
  final Profile profile;

  const RuntimeConfigFragment({
    super.key,
    required this.profile,
  });

  @override
  State<RuntimeConfigFragment> createState() => _RuntimeConfigFragmentState();
}

class _RuntimeConfigFragmentState extends State<RuntimeConfigFragment> {
  String? _content;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRuntimeConfig();
  }

  Future<void> _loadRuntimeConfig() async {
    try {
      final clashConfig = context.read<ClashConfig>();
      final controller = clashConfig.externalController;
      if (controller.isEmpty) {
        setState(() {
          _content = null;
          _isLoading = false;
          _error = 'External controller is not enabled';
        });
        return;
      }
      final dio = Dio(BaseOptions(
        validateStatus: (status) => status != null && status < 500,
      ));
      final baseUrl = 'http://$controller';
      final results = await Future.wait([
        _safeGet(dio, '$baseUrl/configs'),
        _safeGet(dio, '$baseUrl/proxies'),
        _safeGet(dio, '$baseUrl/rules'),
        _safeGet(dio, '$baseUrl/providers/proxies'),
        _safeGet(dio, '$baseUrl/providers/rules'),
      ]);
      final merged = <String, dynamic>{};
      merged['configs'] = results[0];
      final proxiesData = results[1];
      merged['proxies'] = proxiesData;
      merged['rules'] = results[2];
      merged['proxy-providers'] = results[3];
      merged['rule-providers'] = results[4];
      final proxyGroups = <String, dynamic>{};
      if (proxiesData is Map<String, dynamic> && proxiesData.containsKey('proxies')) {
        final proxies = proxiesData['proxies'];
        if (proxies is Map<String, dynamic>) {
          const groupTypes = {'Selector', 'URLTest', 'Fallback', 'LoadBalance'};
          proxies.forEach((name, value) {
            if (value is Map<String, dynamic> && groupTypes.contains(value['type'])) {
              proxyGroups[name] = value;
            }
          });
        }
      }
      merged['proxy-groups'] = proxyGroups;
      final prettyJson =
          const JsonEncoder.withIndent('  ').convert(merged);
      if (!mounted) return;
      setState(() {
        _content = prettyJson;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _content = null;
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<dynamic> _safeGet(Dio dio, String url) async {
    try {
      final response = await dio.get(
        url,
        options: Options(responseType: ResponseType.json),
      );
      if (response.statusCode == HttpStatus.ok) {
        return response.data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(appLocalizations.nullProfileDesc),
      );
    }
    return _JsonViewer(content: _content!);
  }
}

class _JsonViewer extends StatefulWidget {
  final String content;

  const _JsonViewer({required this.content});

  @override
  State<_JsonViewer> createState() => _JsonViewerState();
}

class _JsonViewerState extends State<_JsonViewer> {
  late final CodeLineEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(widget.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeEditor(
      readOnly: true,
      focusNode: _focusNode,
      showCursorWhenReadOnly: false,
      controller: _controller,
      shortcutsActivatorsBuilder: const DefaultCodeShortcutsActivatorsBuilder(),
      indicatorBuilder: (
        context,
        editingController,
        chunkController,
        notifier,
      ) {
        return Row(
          children: [
            DefaultCodeLineNumber(
              controller: editingController,
              notifier: notifier,
            ),
            DefaultCodeChunkIndicator(
              width: 20,
              controller: chunkController,
              notifier: notifier,
            ),
          ],
        );
      },
      style: CodeEditorStyle(
        fontSize: 14,
        codeTheme: CodeHighlightTheme(
          languages: {
            'json': CodeHighlightThemeMode(mode: langJson),
          },
          theme: atomOneLightTheme,
        ),
      ),
    );
  }
}

class LongPressDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onLongPress;
  final Duration duration;

  const LongPressDetector({
    super.key,
    required this.child,
    required this.onLongPress,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<LongPressDetector> createState() => _LongPressDetectorState();
}

class _LongPressDetectorState extends State<LongPressDetector> {
  Stopwatch? _stopwatch;

  void _onPointerDown(PointerDownEvent event) {
    _stopwatch = Stopwatch()..start();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_stopwatch != null && _stopwatch!.elapsed >= widget.duration) {
      widget.onLongPress();
    }
    _stopwatch?.stop();
    _stopwatch = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _stopwatch?.stop();
    _stopwatch = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }
}
