plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.family_monitor"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    flavorDimensions += "app"
    productFlavors {
        create("parent") {
            manifestPlaceholders["dartEntrypoint"] = "main_parent"
            dimension = "app"
            applicationId = "com.example.family_monitor.parent"
            resValue("string", "app_name", "Family Monitor Parent")
        }
        create("child") {
            manifestPlaceholders["dartEntrypoint"] = "main_child"
            dimension = "app"
            applicationId = "com.example.family_monitor.child"
            resValue("string", "app_name", "Family Monitor Child")
        }
    }



    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
// This is already appended by flutter plugin, but entry points need to be set per flavor
