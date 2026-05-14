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

    // AGP 8.x disabled BuildConfig generation by default.
    // Re-enable it so WatchdogService and WatchdogWorker can reference
    // BuildConfig.FLAVOR and BuildConfig.BUILD_TYPE at runtime.
    buildFeatures {
        buildConfig = true
    }

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

        // AND-01: Replace "com.example.family_monitor" with your real reverse-domain
        // application ID before publishing.  Also update google-services.json, all
        // Kotlin package declarations, and the LauncherAlias componentName in
        // MainActivity.kt.

        minSdk = 24

        targetSdk = 35

        versionCode = 1

        versionName = "1.0"

        multiDexEnabled = true
    }

    // SEC-02: Release signing — credentials read from environment variables so
    // the keystore is never checked into source control.
    // Set in CI/CD or local gradle.properties (git-ignored):
    //   KEYSTORE_PATH  KEYSTORE_PASSWORD  KEY_ALIAS  KEY_PASSWORD
    signingConfigs {
        create("release") {
            val ksPath  = System.getenv("KEYSTORE_PATH")     ?: project.findProperty("KEYSTORE_PATH")     as String?
            val ksPwd   = System.getenv("KEYSTORE_PASSWORD") ?: project.findProperty("KEYSTORE_PASSWORD") as String?
            val ksAlias = System.getenv("KEY_ALIAS")         ?: project.findProperty("KEY_ALIAS")         as String?
            val ksKPwd  = System.getenv("KEY_PASSWORD")      ?: project.findProperty("KEY_PASSWORD")      as String?
            if (ksPath != null && ksPwd != null && ksAlias != null && ksKPwd != null) {
                storeFile     = file(ksPath)
                storePassword = ksPwd
                keyAlias      = ksAlias
                keyPassword   = ksKPwd
            } else {
                // Fallback to debug cert in dev; DO NOT publish without setting the env vars.
                storeFile     = file(System.getProperty("user.home") + "/.android/debug.keystore")
                storePassword = "android"
                keyAlias      = "androiddebugkey"
                keyPassword   = "android"
            }
        }
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

            // SEC-02: Use the proper release signing config (see signingConfigs above).
            signingConfig = signingConfigs.getByName("release")

            // SEC-03: Enable R8 code shrinking and obfuscation.
            isMinifyEnabled   = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Upload the R8 mapping file to Firebase Crashlytics automatically
            // so obfuscated stack traces in the console are deobfuscated.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = true
                nativeSymbolUploadEnabled = false
            }
        }

        debug {
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = false
                nativeSymbolUploadEnabled = false
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

    lint {
        lintConfig = file("lint.xml")
        abortOnError = false
        warningsAsErrors = false
        checkReleaseBuilds = false
        baseline = file("lint-baseline.xml")
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
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    implementation(
        "androidx.multidex:multidex:2.0.1"
    )

    // FIX-06: WorkManager as a complementary watchdog alongside AlarmManager.
    // WorkManager survives Doze and Battery Saver on Android 6+ without needing
    // USE_EXACT_ALARM or SCHEDULE_EXACT_ALARM — both of which are restricted on
    // Android 12+ and cause Play Store review rejection.
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // FIX-15: For DevicePolicyManager.setPackagesSuspended (requires API 24+
    // which matches our minSdk=24, no extra dep needed — using built-in DPM API)

}
