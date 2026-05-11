plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {

    namespace =
        "com.example.family_monitor"

    compileSdk = 35

    ndkVersion =
        "27.0.12077973"

    compileOptions {
        sourceCompatibility =
            JavaVersion.VERSION_17

        targetCompatibility =
            JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget =
            JavaVersion.VERSION_17
                .toString()
    }

    defaultConfig {

        applicationId =
            "com.example.family_monitor"

        minSdk = 24

        targetSdk = 35

        versionCode = 1

        versionName = "1.0"

        multiDexEnabled = true
    }

    flavorDimensions += "app"

    productFlavors {

        create("parent") {

            dimension = "app"

            applicationId =
                "com.example.family_monitor.parent"

            manifestPlaceholders[
                "dartEntrypoint"
            ] = "main_parent"

            resValue(
                "string",
                "app_name",
                "Family Monitor Parent",
            )
        }

        create("child") {

            dimension = "app"

            applicationId =
                "com.example.family_monitor.child"

            manifestPlaceholders[
                "dartEntrypoint"
            ] = "main_child"

            resValue(
                "string",
                "app_name",
                "Family Monitor Child",
            )
        }
    }

    buildTypes {

        release {

            signingConfig =
                signingConfigs.getByName(
                    "debug"
                )

            isMinifyEnabled =
                false

            isShrinkResources =
                false
        }
    }

    packaging {

        resources {

            excludes += listOf(
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {

    implementation(
        "androidx.multidex:multidex:2.0.1"
    )
}
