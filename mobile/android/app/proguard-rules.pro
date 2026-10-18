# Pigeon JNI generated in shared_preferences_android 2.5.0 resolves suspend
# methods by their exact JVM descriptors at runtime. R8 otherwise renames the
# Continuation interface to t4, even when the API registrar carries @Keep.
# Keep this one descriptor type stable; do not disable shrinking globally.
-keep class kotlin.coroutines.Continuation { *; }

# jni 1.1.0 kotlin.dart resolves these Kotlin types/members by literal names
# (JClass.forName, GetFieldID, GetStaticFieldID and GetStaticMethodID). R8
# cannot infer those Dart-side lookups from the Kotlin bytecode.
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons
-keep class kotlin.Result { java.lang.Object value; }
-keep class kotlin.Result$Failure {
    java.lang.Throwable exception;
    <init>(java.lang.Throwable);
}
-keep class kotlin.Unit { public static kotlin.Unit INSTANCE; }

# IntrinsicsKt is a facade: the requested static method is declared on its
# superclass IntrinsicsKt__IntrinsicsKt. Preserve both for inherited JNI lookup.
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt__IntrinsicsKt {
    public static java.lang.Object getCOROUTINE_SUSPENDED();
}
