import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mortgageus.calculator"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        @Suppress("DEPRECATION")
        jvmTarget = "17"
    }

    // ── Release signing ───────────────────────────────────────────────────────
    // 1. Generate keystore (see docs/CHECKLIST_LAUNCH.md step 1)
    // 2. Create android/key.properties (already in .gitignore)
    // android/key.properties format:
    //   storePassword=YOUR_STORE_PASSWORD
    //   keyPassword=YOUR_KEY_PASSWORD
    //   keyAlias=mortgageus
    //   storeFile=../keystore/mortgageus-release.jks
    val keystorePropsFile = rootProject.file("key.properties")
    val keystoreProps = Properties()
    if (keystorePropsFile.exists()) {
        keystoreProps.load(keystorePropsFile.inputStream())
    }

    signingConfigs {
        create("release") {
            if (keystorePropsFile.exists()) {
                keyAlias      = keystoreProps["keyAlias"]      as String
                keyPassword   = keystoreProps["keyPassword"]   as String
                storeFile     = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.mortgageus.calculator"
        minSdk        = 24
        targetSdk     = 34
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = if (keystorePropsFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            isMinifyEnabled   = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
