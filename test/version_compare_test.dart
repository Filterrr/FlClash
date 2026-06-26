import 'package:fl_clash/common/version.dart';

void main() {
  _expectEqual(
    compareVersions('v0.8.85+20260624', '0.8.85+20260624'),
    0,
    'release tag with v prefix and identical build should be equal',
  );
  _expectEqual(
    compareVersions('v0.8.85', '0.8.85'),
    0,
    'identical version without build should be equal',
  );
  _expectGreaterThanZero(
    compareVersions('v0.8.85+20260625', '0.8.85+20260624'),
    'higher build should compare as newer',
  );
  _expectGreaterThanZero(
    compareVersions('v0.8.86+20260625', '0.8.85+20260624'),
    'higher patch should compare as newer',
  );
  _expectLessThanZero(
    compareVersions('v0.8.85+20260624', '0.8.86+20260626'),
    'lower remote version should not be treated as update',
  );
}

void _expectEqual(int actual, int expected, String description) {
  if (actual != expected) {
    throw StateError('$description: expected $expected, got $actual');
  }
}

void _expectGreaterThanZero(int actual, String description) {
  if (actual <= 0) {
    throw StateError('$description: expected > 0, got $actual');
  }
}

void _expectLessThanZero(int actual, String description) {
  if (actual >= 0) {
    throw StateError('$description: expected < 0, got $actual');
  }
}
