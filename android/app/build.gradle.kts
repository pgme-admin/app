import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pgme.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pgme.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26  // Required by Zoom SDK
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Enable ProGuard for release builds
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Also apply ProGuard rules in debug mode for testing
            // But don't minify to make debugging easier
            proguardFiles("proguard-rules.pro")
        }
    }

    // Packaging options to handle conflicts and exclude problematic files
    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/*.kotlin_module"
            )
        }

        // Handle native library conflicts (libc++_shared.so)
        jniLibs {
            pickFirsts += setOf("lib/*/libc++_shared.so")
        }
    }

    buildFeatures {
        compose = true
        viewBinding = true
        buildConfig = true
    }
}

// Screen-capture protection is on unless a build explicitly opts out with
// PGME_ALLOW_SCREEN_CAPTURE=true in the environment. Driven by an env var
// rather than a source edit so producing a demo build never means commenting
// out FLAG_SECURE and remembering to put it back — the default is always
// protected, whatever state the working tree is in.
val allowScreenCapture: Boolean = System.getenv("PGME_ALLOW_SCREEN_CAPTURE") == "true"

android.defaultConfig {
    buildConfigField("boolean", "ALLOW_SCREEN_CAPTURE", allowScreenCapture.toString())
}

if (allowScreenCapture) {
    logger.warn("*** PGME: building with screenshots and screen recording ENABLED — do not distribute to students ***")
}

// The release build type silently falls back to the DEBUG key when
// android/key.properties is missing (see buildTypes above). That is fine for
// local development, but a debug-signed "release" APK cannot update or replace
// a release-signed install of com.pgme.app on a device ("App not installed").
// Do not fail the build — just make the situation impossible to miss.
if (!keystorePropertiesFile.exists() &&
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
) {
    logger.warn(
        "\n*** PGME WARNING: a release build was requested but android/key.properties is missing. ***\n" +
        "*** This build will be signed with the DEBUG key, NOT the release key. ***\n" +
        "*** A debug-signed APK cannot update or replace an app installed from a release-signed build ***\n" +
        "*** (Android reports \"App not installed\"), and it must not be shipped to testers or stores. ***\n" +
        "*** Create android/key.properties with the release keystore details to sign properly. ***\n"
    )
}

flutter {
    source = "../.."
}

// Automated Play Store upload (./gradlew publishBundle) via Gradle Play
// Publisher. Only wired up once a service account key is actually present —
// most builds (local dev, CI without publish credentials) never need this,
// and the plugin errors out eagerly if configured against a missing file.
//
// One-time setup (do this in Google Play Console + Google Cloud Console,
// not here):
//   1. Play Console -> Setup -> API access -> link/create a Cloud project.
//   2. "Create new service account" -> in Cloud Console, add a JSON key for
//      it and download it.
//   3. Back in Play Console -> API access -> grant that service account
//      access to this app (Release apps to testing tracks, at minimum).
//   4. Save the downloaded JSON as android/play-service-account.json
//      (already gitignored) or point PLAY_STORE_SERVICE_ACCOUNT_JSON at it.
//
// Then: flutter build appbundle (or shorebird release android) followed by
// `./gradlew publishBundle --track internal` from android/.
val playServiceAccountFile = rootProject.file(
    System.getenv("PLAY_STORE_SERVICE_ACCOUNT_JSON") ?: "play-service-account.json"
)

if (playServiceAccountFile.exists()) {
    apply(plugin = "com.github.triplet.play")
    configure<com.github.triplet.gradle.play.PlayPublisherExtension> {
        serviceAccountCredentials.set(playServiceAccountFile)
        track.set(System.getenv("PLAY_STORE_TRACK") ?: "internal")
        defaultToAppBundles.set(true)
        enabled.set(true)
        commit.set(true)
        resolutionStrategy.set(com.github.triplet.gradle.play.ResolutionStrategy.IGNORE)
    }
} else {
    logger.warn(
        "Play Publisher not configured — no service account file at " +
            "${playServiceAccountFile.path}. Set PLAY_STORE_SERVICE_ACCOUNT_JSON " +
            "or place the key at android/play-service-account.json to enable " +
            "`./gradlew publishBundle`."
    )
}


dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-splashscreen:1.0.1")

    // Zoom SDK dependencies
    implementation("com.github.bumptech.glide:glide:4.15.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.9.0")

    // Jetpack Compose dependencies (required by Zoom SDK UI)
    val composeBom = platform("androidx.compose:compose-bom:2023.10.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")

    // ViewBinding (required by Zoom SDK for screen sharing)
    implementation("androidx.databinding:viewbinding:8.11.1")

    // ExoPlayer (required by Zoom SDK for media playback)
    implementation("androidx.media3:media3-exoplayer:1.2.1")
    implementation("androidx.media3:media3-ui:1.2.1")

    // Lottie (required by Zoom SDK for animations)
    implementation("com.airbnb.android:lottie:6.3.0")

    // ConstraintLayout (required by Zoom SDK)
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}
