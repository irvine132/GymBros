import 'package:flutter/services.dart';
import 'package:jni/jni.dart';

// The Android plugin's Pigeon JNI wrapper puts the original JThrowable in
// details. Read class identities only, with a bounded cause chain.
String nativeDiagnostic(PlatformException error, String Function(Iterable<String>) classify) {
  if (error.code == 'channel-error' || error.code == 'null-error') return error.code;
  if (error.code != 'PlatformException' || error.details is! JThrowable) return 'unknown';
  final names = <String>[];
  JObject? current = error.details as JThrowable;
  var owned = false;
  try {
    final throwableClass = JClass.forName('java/lang/Throwable');
    final classClass = JClass.forName('java/lang/Class');
    try {
      final getCause = throwableClass.instanceMethodId('getCause', '()Ljava/lang/Throwable;');
      final getName = classClass.instanceMethodId('getName', '()Ljava/lang/String;');
      for (var i = 0; i < 3 && current != null; i++) {
        final javaClass = current.jClass;
        try {
          final name = getName.call(javaClass, JString.type, []);
          names.add(name.toDartString(releaseOriginal: true));
        } finally {
          javaClass.release();
        }
        final next = getCause.callNullable(current, JObject.type, []);
        if (owned) current.release();
        current = next;
        owned = next != null;
      }
    } finally {
      throwableClass.release();
      classClass.release();
    }
  } catch (_) {
    // Never obscure the original storage failure or expose the raw exception.
    return 'jni-inspection-failed';
  } finally {
    if (owned) current?.release();
  }
  return names.isEmpty ? 'unknown' : 'jni.getAll:${classify(names)}';
}
