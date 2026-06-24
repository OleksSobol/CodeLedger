import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Auto-increment build number in pubspec.yaml on each build
tasks.register("incrementBuildNumber") {
    doLast {
        val pubspec = file("../../pubspec.yaml")
        val content = pubspec.readText()
        val regex = Regex("""(version:\s*\d+\.\d+\.\d+\+)(\d+)""")
        val match = regex.find(content)
        if (match != null) {
            val oldBuild = match.groupValues[2].toInt()
            val newBuild = oldBuild + 1
            val updated = content.replaceFirst(regex, "${match.groupValues[1]}$newBuild")
            pubspec.writeText(updated)
            println("Build number incremented: $oldBuild → $newBuild")
        }
    }
}

tasks.matching { it.name.startsWith("assemble") }.configureEach {
    dependsOn("incrementBuildNumber")
}

android {
    namespace = "com.osobol.code_ledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.osobol.code_ledger"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePropertiesFile = rootProject.file("key.properties")
            if (keystorePropertiesFile.exists()) {
                val props = Properties().apply { load(keystorePropertiesFile.inputStream()) }
                keyAlias = props["keyAlias"] as String
                keyPassword = props["keyPassword"] as String
                storeFile = file(props["storeFile"] as String)
                storePassword = props["storePassword"] as String
            } else {
                // CI: read from environment variables
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
                storeFile = System.getenv("KEYSTORE_PATH")?.let { file(it) }
                storePassword = System.getenv("STORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val keystorePropertiesFile = rootProject.file("key.properties")
            val hasEnvSigning = System.getenv("KEYSTORE_PATH") != null
            signingConfig = if (keystorePropertiesFile.exists() || hasEnvSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
