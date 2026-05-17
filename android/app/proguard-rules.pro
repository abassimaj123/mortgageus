-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.plugin.platform.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.**

# AdMob / Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }

# Google Play Billing
-keep class com.android.billingclient.** { *; }
-keep interface com.android.billingclient.** { *; }

# Google Play In-App Review
-keep class com.google.android.play.core.review.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# Firebase Analytics + Crashlytics
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.crashlytics.** { *; }
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
