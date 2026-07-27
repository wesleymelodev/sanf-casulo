# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# MediaPipe GenAI
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Workmanager - CRITICAL FIX FOR WorkDatabase_Impl
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }
-dontwarn androidx.work.impl.**
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    public <init>(...);
}

# Android Startup & Lifecycle
-keep class androidx.startup.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.startup.**

# Play Store Split Install (Missing classes fix)
-dontwarn com.google.android.play.core.**

# Standard ProGuard rules for better stability
-keepattributes Signature,Exceptions,*Annotation*
-keep class androidx.annotation.Keep
-keep @androidx.annotation.Keep class * {*;}
-keepclassmembers class * {
  @androidx.annotation.Keep *;
}
