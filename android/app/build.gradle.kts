import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/release-signing.md). Build-time only: nothing here
// ships in the APK. The values come from the untracked android/key.properties
// (storeFile, storePassword, keyAlias, keyPassword), or, e.g. on CI, from the
// Gradle properties releaseStoreFile, releaseStorePassword, releaseKeyAlias
// and releaseKeyPassword (`flutter build apk -P...`). Never commit them, and
// never pass them through --dart-define.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun releaseSigningValue(name: String): String? =
    keyProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: (findProperty("release" + name.replaceFirstChar { it.uppercase() }) as String?)
            ?.takeIf { it.isNotBlank() }

val releaseSigningNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val releaseSigning = releaseSigningNames.associateWith { releaseSigningValue(it) }
val hasReleaseSigning = releaseSigning.values.all { it != null }
if (!hasReleaseSigning && releaseSigning.values.any { it != null }) {
    val missing = releaseSigning.filterValues { it == null }.keys
    throw GradleException("Release signing is partly configured; missing: $missing")
}

android {
    namespace = "sg.smartcommute.sg_smart_commute"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "sg.smartcommute.sg_smart_commute"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getValue("storeFile")!!)
                storePassword = releaseSigning.getValue("storePassword")
                keyAlias = releaseSigning.getValue("keyAlias")
                keyPassword = releaseSigning.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without a release key: local smoke builds only. Such an APK
            // cannot go to Play and cannot update an install signed with the
            // release key.
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

// Warn only when a release variant is actually being built.
if (!hasReleaseSigning) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name.contains("Release") }) {
            logger.warn(
                "WARNING: no release signing configured (android/key.properties); " +
                    "the release build is signed with the DEBUG key. Do not distribute it.",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
