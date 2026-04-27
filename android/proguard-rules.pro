# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google AdMob
-keep class com.google.android.gms.ads.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Play Billing (in_app_purchase)
-keep class com.android.billingclient.** { *; }
-keep interface com.android.billingclient.** { *; }
-keepnames class com.android.billingclient.** { *; }

# Google Play In-App Review
-keep class com.google.android.play.core.review.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# sqflite
-keep class io.flutter.plugins.sqflite.** { *; }
-keep class com.tekartik.sqflite.** { *; }
