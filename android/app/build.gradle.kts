import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun dartDefine(name: String): String? {
    val encodedDefines = (project.findProperty("dart-defines") as? String)
        ?.split(",")
        ?: return null
    for (encoded in encodedDefines) {
        if (encoded.isBlank()) continue
        val decoded = try {
            String(Base64.getDecoder().decode(encoded))
        } catch (_: IllegalArgumentException) {
            continue
        }
        val separator = decoded.indexOf('=')
        if (separator <= 0) continue
        if (decoded.substring(0, separator) == name) {
            return decoded.substring(separator + 1)
        }
    }
    return null
}

val llmTranslationEnabled =
    dartDefine("MESHCORE_ENABLE_TRANSLATION")?.toBooleanStrictOrNull()
        ?: (project.findProperty("meshcore.enableLlmTranslation") as? String)
            ?.toBooleanStrictOrNull()
        ?: true

android {
    namespace = "com.meshcore.mcoadvanced"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "29.0.14206865"

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
        applicationId = "com.meshcore.mcoadvanced"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Codec2 native build removed - no longer needed
        // externalNativeBuild {
        //     cmake {
        //         arguments += listOf("-DANDROID_STL=c++_shared")
        //     }
        // }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ONNX Runtime resolves its Java classes from native code by name.
            // Without these rules R8 renames them and the process SIGABRTs with
            // "java_class == null" the instant the codec runs a model.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        jniLibs {
            if (!llmTranslationEnabled) {
                excludes += listOf(
                    "**/libGemmaModelConstraintProvider.so",
                    "**/libLiteRt*.so",
                    "**/libggml*.so",
                    "**/libllama*.so",
                    "**/libllamadart.so",
                    "**/libmtmd.so"
                )
            }
        }
    }

    // Codec2 native build removed - no longer needed
    // externalNativeBuild {
    //     cmake {
    //         path = file("src/main/cpp/CMakeLists.txt")
    //     }
    // }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
