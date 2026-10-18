# Pigeon JNI generated in shared_preferences_android 2.5.0 resolves suspend
# methods by their exact JVM descriptors at runtime. R8 otherwise renames the
# Continuation interface to t4, even when the API registrar carries @Keep.
# Keep this one descriptor type stable; do not disable shrinking globally.
-keep class kotlin.coroutines.Continuation { *; }
