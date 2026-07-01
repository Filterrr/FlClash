import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/update.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

/// 格式化字节数为人类可读字符串。
String _formatBytes(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
  if (bytes < 1024 * 1024 * 1024) {
    return "${(bytes / 1024 / 1024).toStringAsFixed(1)} MB";
  }
  return "${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB";
}

/// 格式化发布时间为 YYYY-MM-DD。
String _formatDate(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

/// 更新对话框的可变状态。
///
/// Controller 通过持有 [ValueNotifier]<UpdateDialogState> 并更新其 value
/// 来驱动 [UpdateDialog] 的 UI 切换。见 [showUpdateDialog]。
class UpdateDialogState {
  final UpdateStatus status;
  final DownloadProgress? progress;
  final String? errorMessage;

  const UpdateDialogState({
    required this.status,
    this.progress,
    this.errorMessage,
  });

  UpdateDialogState copyWith({
    UpdateStatus? status,
    DownloadProgress? progress,
    String? errorMessage,
  }) {
    return UpdateDialogState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 更新流程对话框。
///
/// 纯展示组件,根据 [status] 切换 6 个状态视图:
/// available / downloading / verifying / installing / failed / readyToRestart。
/// 状态变化由外部驱动(通过 [showUpdateDialog] + [ValueNotifier],
/// 或由 Controller 自行用 [globalState.showCommonDialog] 包裹并重建)。
class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final UpdateStatus status;
  final DownloadProgress? progress;
  final String? errorMessage;
  final VoidCallback? onUpdate;
  final VoidCallback? onRetry;
  final VoidCallback? onRestart;
  final VoidCallback? onCancel;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.status,
    this.progress,
    this.errorMessage,
    this.onUpdate,
    this.onRetry,
    this.onRestart,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title()),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 320),
        child: _buildContent(context),
      ),
      actions: _buildActions(context),
    );
  }

  String _title() {
    switch (status) {
      case UpdateStatus.available:
        return appLocalizations.newVersionAvailable;
      case UpdateStatus.downloading:
        return appLocalizations.downloadingUpdate;
      case UpdateStatus.verifying:
        return appLocalizations.verifyingIntegrity;
      case UpdateStatus.installing:
        return appLocalizations.installingUpdate;
      case UpdateStatus.failed:
        return appLocalizations.updateFailed;
      case UpdateStatus.readyToRestart:
        return appLocalizations.updateCompleted;
      default:
        return appLocalizations.newVersionAvailable;
    }
  }

  Widget _buildContent(BuildContext context) {
    switch (status) {
      case UpdateStatus.available:
        return _buildAvailableContent(context);
      case UpdateStatus.downloading:
        return _buildDownloadingContent(context);
      case UpdateStatus.verifying:
        return _buildVerifyingContent(context);
      case UpdateStatus.installing:
        return _buildInstallingContent(context);
      case UpdateStatus.failed:
        return _buildFailedContent(context);
      case UpdateStatus.readyToRestart:
        return _buildReadyToRestartContent(context);
      default:
        return _buildAvailableContent(context);
    }
  }

  Widget _buildAvailableContent(BuildContext context) {
    final paragraphs = updateInfo.releaseNotes
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'v${updateInfo.version}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(updateInfo.publishedAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            appLocalizations.releaseNotes,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(p),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadingContent(BuildContext context) {
    final p = progress;
    final percent = p != null ? (p.percent * 100).toStringAsFixed(1) : '0.0';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        LinearProgressIndicator(value: p?.percent),
        const SizedBox(height: 16),
        Text(
          '$percent%',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (p != null)
          Text(
            '${_formatBytes(p.downloaded)} / ${_formatBytes(p.total)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 4),
        if (p != null)
          Text(
            '${_formatBytes(p.speed)}/s',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  Widget _buildVerifyingContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(appLocalizations.verifyingIntegrity),
        ],
      ),
    );
  }

  Widget _buildInstallingContent(BuildContext context) {
    final hint = Platform.isAndroid
        ? appLocalizations.installHintAndroid
        : appLocalizations.installHintWindows;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(appLocalizations.installingUpdate),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildFailedContent(BuildContext context) {
    return SingleChildScrollView(
      child: SelectableText(
        errorMessage ?? '',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildReadyToRestartContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 16),
          Text(
            appLocalizations.updateCompleted,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    void cancel() {
      (onCancel ?? () => Navigator.of(context).pop())();
    }

    switch (status) {
      case UpdateStatus.available:
        return [
          TextButton(onPressed: cancel, child: Text(appLocalizations.later)),
          FilledButton(
            onPressed: onUpdate,
            child: Text(appLocalizations.updateNow),
          ),
        ];
      case UpdateStatus.downloading:
        return [
          TextButton(
            onPressed: cancel,
            child: Text(appLocalizations.cancelUpdate),
          ),
        ];
      case UpdateStatus.verifying:
      case UpdateStatus.installing:
        return const [];
      case UpdateStatus.failed:
        return [
          TextButton(
            onPressed: cancel,
            child: Text(appLocalizations.cancelUpdate),
          ),
          FilledButton(
            onPressed: onRetry,
            child: Text(appLocalizations.retry),
          ),
        ];
      case UpdateStatus.readyToRestart:
        return [
          TextButton(onPressed: cancel, child: Text(appLocalizations.later)),
          FilledButton(
            onPressed: onRestart,
            child: Text(appLocalizations.restartNow),
          ),
        ];
      default:
        return [
          TextButton(onPressed: cancel, child: Text(appLocalizations.later)),
        ];
    }
  }
}

/// 显示更新对话框的便捷函数。
///
/// Controller 用法:
/// ```dart
/// final state = ValueNotifier(
///   const UpdateDialogState(status: UpdateStatus.available),
/// );
/// showUpdateDialog(
///   context: context,
///   updateInfo: info,
///   state: state,
///   onUpdate: () => controller.start(state),
///   onRetry: () => controller.retry(state),
///   onRestart: () => controller.restart(),
///   onCancel: () => controller.cancel(),
/// );
/// // 驱动状态变化:
/// state.value = state.value.copyWith(
///   status: UpdateStatus.downloading,
///   progress: progress,
/// );
/// ```
///
/// 若不传入 [state],对话框只静态显示 available 状态(可用于预览/测试)。
Future<void> showUpdateDialog({
  required BuildContext context,
  required UpdateInfo updateInfo,
  ValueNotifier<UpdateDialogState>? state,
  VoidCallback? onUpdate,
  VoidCallback? onRetry,
  VoidCallback? onRestart,
  VoidCallback? onCancel,
  bool dismissible = false,
}) {
  final notifier = state ??
      ValueNotifier(
        const UpdateDialogState(status: UpdateStatus.available),
      );
  return globalState.showCommonDialog(
    dismissible: dismissible,
    child: ValueListenableBuilder<UpdateDialogState>(
      valueListenable: notifier,
      builder: (context, value, _) {
        return UpdateDialog(
          updateInfo: updateInfo,
          status: value.status,
          progress: value.progress,
          errorMessage: value.errorMessage,
          onUpdate: onUpdate,
          onRetry: onRetry,
          onRestart: onRestart,
          onCancel: onCancel,
        );
      },
    ),
  );
}
