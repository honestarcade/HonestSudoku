import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from the environment, never from a file in the tree:
// there is no key.properties to leak and no literal to grep for.
//
// Three behaviours, deliberately different:
//   * all four HS_* set          -> sign with the upload key
//   * none set, HS_RELEASE unset -> fall back to the debug key and WARN, so
//                                   `flutter run --release` still works locally
//   * HS_RELEASE=1, any missing  -> fail configuration naming the variable, so
//                                   an unsigned bundle can never reach Play by
//                                   accident
val hsSigningVars = listOf("HS_KEYSTORE_PATH", "HS_KEYSTORE_PASS", "HS_KEY_ALIAS", "HS_KEY_PASS")
val hsPresent = hsSigningVars.filter { !System.getenv(it).isNullOrBlank() }
val hsReleaseRequested = System.getenv("HS_RELEASE") == "1"
val hsSigningComplete = hsPresent.size == hsSigningVars.size

// The verdict, written to a file the gate names, rather than said in the log
// and grepped back.
//
// The log is not ours. `JAVA_TOOL_OPTIONS='-Dhs="signed with the UPLOAD key"'`
// makes the JVM print "Picked up JAVA_TOOL_OPTIONS: ..." before Gradle starts,
// which matched the gate's unanchored grep: a debug-signed bundle reported as
// upload-signed, GATE PASSED, exit 0. The same variable made a correct build
// fail. `_JAVA_OPTIONS` behaves identically, and any future log line
// containing the phrase has the same effect (#120).
//
// This file is created by the gate, passed in by name, and written only here.
// The println lines stay: they are for a human reading the build output, and
// nothing keys off them any more.
fun hsWriteVerdict(verdict: String) {
    val path = System.getenv("HS_SIGNING_VERDICT") ?: return
    runCatching { File(path).writeText(verdict) }
        .onFailure { logger.warn("could not write HS_SIGNING_VERDICT: ${it.message}") }
}

// Partly set is always an error, in any mode: it almost certainly means a typo
// in the variable name, and silently signing with the debug key would hide it.
if (hsPresent.isNotEmpty() && !hsSigningComplete) {
    val missing = hsSigningVars.first { System.getenv(it).isNullOrBlank() }
    throw GradleException("$missing is not set")
}
if (hsReleaseRequested && !hsSigningComplete) {
    val missing = hsSigningVars.first { System.getenv(it).isNullOrBlank() }
    throw GradleException("$missing is not set")
}
if (hsReleaseRequested) {
    val keystore = file(System.getenv("HS_KEYSTORE_PATH"))
    if (!keystore.exists() || !keystore.canRead()) {
        throw GradleException("HS_KEYSTORE_PATH does not exist: ${keystore.path}")
    }
}

android {
    namespace = "com.honestarcade.sudoku"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.honestarcade.sudoku"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Flutter 3.47 default, pinned deliberately; see .n8/decisions.md
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hsSigningComplete) {
            create("release") {
                storeFile = file(System.getenv("HS_KEYSTORE_PATH"))
                storePassword = System.getenv("HS_KEYSTORE_PASS")
                keyAlias = System.getenv("HS_KEY_ALIAS")
                keyPassword = System.getenv("HS_KEY_PASS")
            }
        }
    }

    buildTypes {
        release {
            if (hsSigningComplete) {
                // Said out loud, for the same reason the fallback below is:
                // tools/gate.sh reads this line back and fails if its own
                // prediction disagreed. Two definitions of "is this variable
                // set" drifted apart twice (#91, #106); now a disagreement is
                // itself a gate failure rather than a silent lie.
                hsWriteVerdict("upload")
                println("HS_* signing variables set — release build signed with the UPLOAD key")
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Both, deliberately. logger.warn is the Gradle-idiomatic
                // call, but `flutter build` filters warn-level output at its
                // default verbosity (visible only with -v), and a warning
                // nobody sees cannot do the job it exists for.
                hsWriteVerdict("debug")
                logger.warn("HS_* signing variables not set — release build signed with the DEBUG key; set HS_RELEASE=1 to make this an error")
                println("HS_* signing variables not set — release build signed with the DEBUG key; set HS_RELEASE=1 to make this an error")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
        // profile stays on debug signing deliberately; it is never uploaded.
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
