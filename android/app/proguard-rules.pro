# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep all app classes — MethodChannel callbacks must not be stripped
-keep class com.clicker.app.** { *; }

# ONNX Runtime
-keep class ai.onnxruntime.** { *; }

# ML Kit
-keep class com.google.mlkit.** { *; }

# Play Core (referenced by Flutter but not always included)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep native method declarations
-keepclasseswithmembernames class * {
    native <methods>;
}
