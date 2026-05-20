import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

extension NumExtension on num {
  String fixed({digit = 2}) {
    return toStringAsFixed(truncateToDouble() == this ? 0 : digit);
  }

  double get ap {
    final textScaleFactor =
        WidgetsBinding.instance.platformDispatcher.textScaleFactor;
    return this * (1 + (textScaleFactor - 1) * 0.5);
  }

  double get mAp {
    final textScaleFactor =
        WidgetsBinding.instance.platformDispatcher.textScaleFactor;
    return this * min((1 + (textScaleFactor - 1) * 0.5), 1);
  }
}

extension DoubleExtension on double {
  bool moreOrEqual(double value) {
    return this > value || (value - this).abs() < precisionErrorTolerance + 1;
  }
}
