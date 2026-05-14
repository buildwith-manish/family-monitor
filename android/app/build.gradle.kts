plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {

    namespace =
        "com.example.family_monitor"

    compileSdk = 36

    ndkVersion =
        "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
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

        debug {
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
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

// Fallback APK copy for AGP 8.7+ artifact API compatibility
afterEvaluate {
    android.applicationVariants.configureEach {
        val variant = this

        if (variant.buildType.name == "release") {

            tasks.named(
                "assemble${variant.name.replaceFirstChar { it.uppercaseChar() }}"
            ) {

                doLast {

                    val flutterApkDir = File(
                        rootProject.rootDir.parentFile,
                        "build/app/outputs/flutter-apk"
                    )

                    flutterApkDir.mkdirs()

                    variant.outputs.forEach { output ->

                        val apk =
                            (output as com.android.build.gradle.api.ApkVariantOutput)
                                .outputFile

                        if (apk.exists()) {

                            val flavor =
                                if (variant.flavorName.isNullOrBlank())
                                    "app"
                                else
                                    variant.flavorName

                            val dest = File(
                                flutterApkDir,
                                "app-${flavor}-release.apk"
                            )

                            apk.copyTo(dest, overwrite = true)

                            println(
                                "flutter-apk copy: ${apk.name} -> ${dest.name}"
                            )
                        }
                    }
                }
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    implementation(
        "androidx.multidex:multidex:2.0.1"
    )

}
