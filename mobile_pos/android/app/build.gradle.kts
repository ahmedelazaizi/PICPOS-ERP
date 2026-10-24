import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (ARCHITECTURE-M section 4.3): key.properties points at an upload
// keystore kept outside the repository. Release tasks fail closed when the
// file, required properties, or referenced keystore is missing. Debug tasks do
// not require release credentials.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requiredSigningProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasUploadKey = if (keystorePropertiesFile.isFile) {
    try {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
        requiredSigningProperties.all { !keystoreProperties.getProperty(it).isNullOrBlank() } &&
            rootProject.file(keystoreProperties.getProperty("storeFile")).isFile
    } catch (_: Exception) {
        false
    }
} else {
    false
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        check(hasUploadKey) {
            "Release signing is required. Provide a valid android/key.properties " +
                "with storeFile, storePassword, keyAlias, and keyPassword pointing " +
                "to an existing upload keystore. Debug builds remain unaffected."
        }
    }
}

tasks.configureEach {
    if (name.contains("Release", ignoreCase = true) &&
        (name.startsWith("assemble") || name.startsWith("bundle") ||
            name.startsWith("package") || name.startsWith("sign"))) {
        dependsOn(validateReleaseSigning)
    }
}

android {
    namespace = "com.picpos.pos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Permanent once published on Google Play.
        applicationId = "com.picpos.pos"
        // flutter_secure_storage 11 (Keystore-held DB key) needs API 24.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key. The release validation task
            // provides the actionable failure when this config is incomplete.
            if (hasUploadKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
