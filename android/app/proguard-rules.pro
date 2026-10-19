# Zoom SDK ProGuard Rules
# Keep all Zoom SDK classes
-keep class com.zipow.** { *; }
-keep class us.zoom.** { *; }

# Prevent obfuscation of Zoom SDK internals
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Keep Zoom SDK native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Ignore warnings for missing Zebra EMDK (enterprise device SDK)
# This SDK is optional and only needed for Zebra enterprise devices
-dontwarn com.symbol.emdk.**
-dontwarn com.zipow.videobox.ptapp.**

# Keep Zoom SDK listeners and callbacks
-keep class * implements us.zoom.sdk.** { *; }
-keep interface us.zoom.sdk.** { *; }

# Keep Zoom SDK models and data classes
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep WebRTC classes (used by Zoom for video/audio)
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Keep Glide (image loading library used by Zoom)
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
 <init>(...);
}
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-keep class com.bumptech.glide.load.data.ParcelFileDescriptorRewinder$InternalRewinder {
  *** rewind();
}

# Kotlin coroutines (used by Zoom SDK)
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keep class kotlinx.coroutines.** { *; }

# AndroidX and support libraries
-keep class androidx.** { *; }
-dontwarn androidx.**

# Prevent stripping of view binding classes
-keep class * extends androidx.viewbinding.ViewBinding {
    public static *** bind(android.view.View);
    public static *** inflate(android.view.LayoutInflater);
}

# Keep Jetpack Compose (required by Zoom SDK UI)
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**

# Lottie animations (used by Zoom SDK)
-keep class com.airbnb.lottie.** { *; }
-dontwarn com.airbnb.lottie.**

# ExoPlayer (used by Zoom SDK for media playback)
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Zoom SDK transitive deps that ARE declared in the plugin's libs/build.gradle
# (RxJava3, BlueParrott). These need -keep, not -dontwarn — without keep, R8
# strips the classes (nothing in our app code references them directly) and
# the SDK crashes at runtime with NoClassDefFoundError the moment a chat
# fragment opens or a Bluetooth headset event fires. -dontwarn alone only
# silences the build warning, it does NOT pull the classes into the APK.
-keep class io.reactivex.rxjava3.** { *; }
-dontwarn io.reactivex.rxjava3.**
-keep class com.blueparrott.blueparrottsdk.** { *; }
-dontwarn com.blueparrott.blueparrottsdk.**

# Tink crypto — declared in plugin deps; keep its reflective entry points
# so the AndroidKeystoreAesGcm path doesn't break under R8 shrink.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Zoom SDK genuinely-optional features we do NOT use (Intune MDM, in-app
# billing, ML Kit, Play Core, Microsoft Intune lib, Zoom third-party
# integrations, Coil, subsampling-scale-image, javax model). These are
# genuinely absent from the APK; -dontwarn just suppresses build warnings.
-dontwarn coil.compose.SingletonAsyncImageKt
-dontwarn com.android.billingclient.api.**
-dontwarn com.davemorrissey.labs.subscaleview.**
-dontwarn com.google.android.play.core.**
-dontwarn com.google.firebase.**
-dontwarn com.google.mlkit.vision.**
-dontwarn com.google.zxing.**
-dontwarn com.microsoft.intune.**
-dontwarn com.zipow.cnthirdparty.**
-dontwarn javax.lang.model.**
-dontwarn us.zoom.intunelib.**
-dontwarn us.zoom.thirdparty.**
