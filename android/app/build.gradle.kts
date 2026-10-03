import java.util.Properties
import java.io.FileInputStream
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}
val signingFile = rootProject.file("key.properties")
val signingProperties = Properties()
if (signingFile.exists()) FileInputStream(signingFile).use { signingProperties.load(it) }
android {
    namespace = "app.grit.grit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions { sourceCompatibility = JavaVersion.VERSION_11; targetCompatibility = JavaVersion.VERSION_11 }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_11.toString() }
    defaultConfig {
        applicationId = "app.grit.grit"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (signingFile.exists()) create("release") {
            keyAlias = signingProperties["keyAlias"] as String
            keyPassword = signingProperties["keyPassword"] as String
            storeFile = file(signingProperties["storeFile"] as String)
            storePassword = signingProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            if (signingFile.exists()) signingConfig = signingConfigs.getByName("release")
        }
    }
}
flutter { source = "../.." }
