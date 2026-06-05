import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Wrapper for C strings returned by CGO exports (e.g. C.CString).
///
/// Uses [NativeFinalizer] to guarantee memory is freed even if
/// [toDartString] throws or the caller forgets to read the value.
/// On the normal path, [toDartString] detaches the finalizer and
/// frees immediately for deterministic, low-latency cleanup.
class CStringWrapper implements Finalizable {
  final Pointer<Char> _ptr;
  final void Function(Pointer<Char>) _freeFn;
  static NativeFinalizer? _finalizerCache;
  static Pointer<NativeFunction<Void Function(Pointer<Char>)>>? _freeCStringNativePtr;

  CStringWrapper(this._ptr, this._freeFn) {
    _ensureFinalizer();
    _finalizerCache!.attach(this, _ptr.cast(), detach: this);
  }

  static void _ensureFinalizer() {
    if (_finalizerCache != null) return;
    _finalizerCache = NativeFinalizer(_freeCStringNativePtr!);
  }

  /// Must be called once during app initialization with the native pointer
  /// to the `freeCString` function from the loaded dynamic library.
  static void init(
    Pointer<NativeFunction<Void Function(Pointer<Char>)>> freeCStringNativePtr,
  ) {
    _freeCStringNativePtr = freeCStringNativePtr;
  }

  /// Reads the C string as a Dart [String] and frees the native memory.
  ///
  /// On success the [NativeFinalizer] is detached and the pointer is freed
  /// immediately.  If [toDartString] throws, the finalizer will free the
  /// memory when this object is garbage-collected.
  String toDartString() {
    final result = _ptr.cast<Utf8>().toDartString();
    _finalizerCache!.detach(this);
    _freeFn(_ptr);
    return result;
  }
}
