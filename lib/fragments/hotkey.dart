import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/card.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:fl_clash/widgets/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

extension IntlExt on Intl {
  static actionMessage(String messageText) =>
      Intl.message("action_$messageText");
}

class HotKeyFragment extends StatelessWidget {
  const HotKeyFragment({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: HotAction.values.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return SettingsSection(
            label: appLocalizations.hotkeyManagement,
            children: [
              for (final hotAction in HotAction.values)
                _buildHotKeyItem(hotAction),
            ],
          );
        }
        return const SettingsBottomSpace();
      },
    );
  }

  Widget _buildHotKeyItem(HotAction hotAction) {
    return Selector<Config, HotKeyAction>(
      selector: (_, config) {
        final index = config.hotKeyActions.indexWhere(
          (item) => item.action == hotAction,
        );
        return index != -1
            ? config.hotKeyActions[index]
            : HotKeyAction(
                action: hotAction,
              );
      },
      builder: (_, value, __) {
        return Builder(
          builder: (context) {
            final colorScheme = context.colorScheme;
            final keys = _getKeyWidgets(context, value);
            return ListItem(
              title: Text(IntlExt.actionMessage(hotAction.name)),
              onTap: () {
                globalState.showCommonDialog(
                  child: HotKeyRecorder(
                    hotKeyAction: value,
                  ),
                );
              },
              trailing: keys.isEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          appLocalizations.noHotKey,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: keys,
                    ),
            );
          },
        );
      },
    );
  }

  List<Widget> _getKeyWidgets(BuildContext context, HotKeyAction hotKeyAction) {
    final key = hotKeyAction.key;
    if (key == null) return [];
    final colorScheme = context.colorScheme;
    final labels = <String>[
      ...hotKeyAction.modifiers.map((item) => item.physicalKeys.first.label),
      PhysicalKeyboardKey(key).label,
    ];
    return [
      for (var index = 0; index < labels.length; index++) ...[
        if (index > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              "+",
              style: context.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.opacity60,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: colorScheme.outlineVariant.opacity60,
            ),
          ),
          child: Text(
            labels[index],
            style: context.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ];
  }
}

class HotKeyRecorder extends StatefulWidget {
  final HotKeyAction hotKeyAction;

  const HotKeyRecorder({
    super.key,
    required this.hotKeyAction,
  });

  @override
  State<HotKeyRecorder> createState() => _HotKeyRecorderState();
}

class _HotKeyRecorderState extends State<HotKeyRecorder> {
  late ValueNotifier<HotKeyAction> hotKeyActionNotifier;

  @override
  void initState() {
    super.initState();
    hotKeyActionNotifier = ValueNotifier<HotKeyAction>(
      widget.hotKeyAction.copyWith(),
    );
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  bool _handleKeyEvent(KeyEvent keyEvent) {
    if (keyEvent is KeyUpEvent) return false;
    final keys = HardwareKeyboard.instance.physicalKeysPressed;

    final key = keyEvent.physicalKey;

    final modifiers = KeyboardModifier.values
        .where((e) =>
            e.physicalKeys.any(keys.contains) && !e.physicalKeys.contains(key))
        .toSet();
    hotKeyActionNotifier.value = hotKeyActionNotifier.value.copyWith(
      modifiers: modifiers,
      key: key.usbHidUsage,
    );
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  _handleRemove() {
    Navigator.of(context).pop();
    final config = globalState.appController.config;
    config.updateOrAddHotKeyAction(
      hotKeyActionNotifier.value.copyWith(
        modifiers: {},
        key: null,
      ),
    );
  }

  _handleConfirm() {
    Navigator.of(context).pop();
    final config = globalState.appController.config;
    final currentHotkeyAction = hotKeyActionNotifier.value;
    if (currentHotkeyAction.key == null ||
        currentHotkeyAction.modifiers.isEmpty) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(text: appLocalizations.inputCorrectHotkey),
      );
      return;
    }
    final hotKeyActions = config.hotKeyActions;
    final index = hotKeyActions.indexWhere(
      (item) =>
          item.key == currentHotkeyAction.key &&
          keyboardModifierListEquality.equals(
            item.modifiers,
            currentHotkeyAction.modifiers,
          ),
    );
    if (index != -1) {
      globalState.showMessage(
        title: appLocalizations.tip,
        message: TextSpan(text: appLocalizations.hotkeyConflict),
      );
      return;
    }
    config.updateOrAddHotKeyAction(
      currentHotkeyAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(IntlExt.actionMessage((widget.hotKeyAction.action.name))),
      content: ValueListenableBuilder(
        valueListenable: hotKeyActionNotifier,
        builder: (_, hotKeyAction, ___) {
          final key = hotKeyAction.key;
          final modifiers = hotKeyAction.modifiers;
          return SizedBox(
            width: dialogCommonWidth,
            child: key != null
                ? Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final modifier in modifiers)
                        KeyboardKeyBox(
                          keyboardKey: modifier.physicalKeys.first,
                        ),
                      if (modifiers.isNotEmpty)
                        Text(
                          "+",
                          style: context.textTheme.titleMedium,
                        ),
                      KeyboardKeyBox(
                        keyboardKey: PhysicalKeyboardKey(key),
                      ),
                    ],
                  )
                : Text(
                    appLocalizations.pressKeyboard,
                    style: context.textTheme.titleMedium,
                  ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            _handleRemove();
          },
          child: Text(appLocalizations.remove),
        ),
        const SizedBox(
          width: 8,
        ),
        TextButton(
          onPressed: () {
            _handleConfirm();
          },
          child: Text(
            appLocalizations.confirm,
          ),
        ),
      ],
    );
  }
}

class KeyboardKeyBox extends StatelessWidget {
  final KeyboardKey keyboardKey;

  const KeyboardKeyBox({
    super.key,
    required this.keyboardKey,
  });

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          keyboardKey.label,
          style: const TextStyle(
            fontSize: 16,
          ),
        ),
      ),
      onPressed: () {},
    );
  }
}
