import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/material.dart';
import 'package:emoji_regex/emoji_regex.dart';

import '../state.dart';

class TooltipText extends StatelessWidget {
  final Text text;

  const TooltipText({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, container) {
        final maxWidth = container.maxWidth;
        final size = globalState.measure.computeTextSize(
          text,
        );
        if (maxWidth < size.width) {
          return Tooltip(
            preferBelow: false,
            message: text.data,
            child: text,
          );
        }
        return text;
      },
    );
  }
}

class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const EmojiText(
    this.text, {
    super.key,
    this.maxLines,
    this.overflow,
    this.style,
  });

  static bool _isSurrogatePair(String text) {
    return text.codeUnits.length != text.runes.length;
  }

  List<TextSpan> _buildTextSpans() {
    if (!_isSurrogatePair(text) && !_hasExtendedPictographic(text)) {
      return [TextSpan(text: text, style: style)];
    }
    final List<TextSpan> spans = [];
    final matches = emojiRegex().allMatches(text);

    int lastMatchEnd = 0;
    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: style,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: style?.copyWith(
            fontFamily: FontFamily.twEmoji.value,
          ),
        ),
      );
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastMatchEnd),
          style: style,
        ),
      );
    }

    return spans;
  }

  static bool _hasExtendedPictographic(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x1F000 && rune <= 0x1FFFF) ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          (rune >= 0x2300 && rune <= 0x23FF) ||
          (rune >= 0x2B50 && rune <= 0x2B55) ||
          (rune >= 0xFE00 && rune <= 0xFE0F) ||
          (rune >= 0x1F900 && rune <= 0x1F9FF) ||
          (rune >= 0x1FA00 && rune <= 0x1FAFF)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        children: _buildTextSpans(),
      ),
    );
  }
}