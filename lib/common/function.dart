import 'dart:async';

import 'package:flutter/foundation.dart';

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void call(Function action, List<dynamic> positionalArguments, [Map<Symbol, dynamic>? namedArguments]) {
    _timer?.cancel();
    _timer = Timer(delay, () => Function.apply(action, positionalArguments, namedArguments));
  }
}

Function debounce<F extends Function>(F func,{int milliseconds = 600}) {
  Timer? timer;

  return ([List<dynamic>? args, Map<Symbol, dynamic>? namedArgs]) {
    if (timer != null) {
      timer!.cancel();
    }
    timer = Timer(Duration(milliseconds: milliseconds), () async {
      try {
        await Function.apply(func, args ?? [], namedArgs);
      } catch (e) {
        // 避免 debounce 回调中的异步异常成为未处理的 Future 错误
        debugPrint('debounced task failed: $e');
      }
    });
  };
}