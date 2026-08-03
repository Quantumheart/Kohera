# ── Flutter ──────────────────────────────────────────────────
# GeneratedPluginRegistrant is annotated @Keep but be explicit.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }

# ── Play Core deferred components (not used) ─────────────────
# Flutter's embedding engine references Google Play Core split-install
# classes (FlutterPlayStoreSplitApplication, PlayStoreDeferredComponentManager)
# for deferred component / dynamic feature module support. This app does not
# ship deferred components, so the Play Core dependency is absent. R8 full mode
# (default since AGP 8.0) treats missing classes as errors, so suppress them.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-dontwarn com.google.android.play.core.**

# ── Dart-JNI bridge (reflection-heavy) ──────────────────────
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class com.github.dart_lang.** { *; }

# ── Flutter plugins (registered via reflection) ─────────────
# Keep all plugin entry-point classes so R8 doesn't strip them
# before GeneratedPluginRegistrant can add them.
-keep class com.ryanheise.audio_session.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-keep class one.mixin.desktop.drop.** { *; }
-keep class dev.fluttercommunity.plus.device_info.** { *; }
-keep class io.material.plugins.dynamic_color.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class de.julianassmann.flutter_background.** { *; }
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class io.livekit.plugin.** { *; }
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class one.mixin.pasteboard.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.llfbandit.record.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class eu.simonbinder.sqlite3_flutter_libs.** { *; }
-keep class org.unifiedpush.flutter.connector.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class dev.fluttercommunity.plus.wakelock.** { *; }
-keep class com.example.webcrypto.** { *; }

# ── WebRTC native bridge (JNI calls via reflection) ─────────
-keep class org.webrtc.** { *; }
-keepclassmembers class org.webrtc.** {
    native <methods>;
}

# ── Native method preservation ──────────────────────────────
# Any class with native methods must be kept.
-keepclasseswithmembers class * {
    native <methods>;
}

# ── Serialization / Gson / Parcelable ───────────────────────
# Some plugins use Gson/Parcelable for serializing data across
# the platform channel boundary.
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# ── Enums (plugin channels often pass enum names) ──────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}