import 'package:flutter/services.dart';

// No dart:ffi on the web. Keep only Pigeon codes from a fixed list.
String nativeDiagnostic(PlatformException error, String Function(Iterable<String>) classify) {
  if (error.code == 'channel-error' || error.code == 'null-error') return error.code;
  return 'unknown';
}
