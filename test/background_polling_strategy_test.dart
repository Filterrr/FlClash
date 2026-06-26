import 'package:fl_clash/common/low_memory_mode.dart';
import 'package:fl_clash/fragments/background_polling_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePollingMode', () {
    test('returns stopped when app is in background', () {
      final mode = resolvePollingMode(
        isVisible: true,
        isInBackground: true,
        lowMemoryMode: LowMemoryMode.reduced,
      );

      expect(mode, PollingMode.stopped);
    });

    test('returns stopped when page is not visible', () {
      final mode = resolvePollingMode(
        isVisible: false,
        isInBackground: false,
        lowMemoryMode: LowMemoryMode.normal,
      );

      expect(mode, PollingMode.stopped);
    });

    test('returns stopped in low memory mode', () {
      final mode = resolvePollingMode(
        isVisible: true,
        isInBackground: false,
        lowMemoryMode: LowMemoryMode.low,
      );

      expect(mode, PollingMode.stopped);
    });

    test('returns reduced in reduced memory mode', () {
      final mode = resolvePollingMode(
        isVisible: true,
        isInBackground: false,
        lowMemoryMode: LowMemoryMode.reduced,
      );

      expect(mode, PollingMode.reduced);
    });

    test('returns normal in foreground normal mode', () {
      final mode = resolvePollingMode(
        isVisible: true,
        isInBackground: false,
        lowMemoryMode: LowMemoryMode.normal,
      );

      expect(mode, PollingMode.normal);
    });
  });
}
