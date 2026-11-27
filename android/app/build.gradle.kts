import com.android.build.api.dsl.ApplicationExtension
import org.gradle.api.GradleException
import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun resolveKeystoreFile(path: String): File {
    val rootCandidate = rootProject.file(path)
    return if (rootCandidate.exists()) rootCandidate else file(path)
}

data class ReleaseSigningConfig(
    val storeFile: File,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun validateAndBuildSigningConfig(
    sourceLabel: String,
    storeFilePath: String,
    storePassword: String,
    keyAlias: String,
    keyPassword: String,
): ReleaseSigningConfig {
    if (storeFilePath.isEmpty() || storePassword.isEmpty() || keyAlias.isEmpty()) {
        throw GradleException(
            "Incomplete release signing configuration in $sourceLabel."
        )
    }
    val keystoreFile = resolveKeystoreFile(storeFilePath)
    if (!keystoreFile.exists()) {
        throw GradleException("Release keystore from $sourceLabel not found: ${keystoreFile.absolutePath}")
    }
    return ReleaseSigningConfig(
        storeFile = keystoreFile,
        storePassword = storePassword,
        keyAlias = keyAlias,
        keyPassword = keyPassword.ifEmpty { storePassword },
    )
}

fun loadReleaseSigningConfig(): ReleaseSigningConfig? {
    val envPath = System.getenv("KEYSTORE_PATH")?.trim().orEmpty()
    val envStorePass = System.getenv("KEYSTORE_PASSWORD")?.trim().orEmpty()
    val envAlias = System.getenv("KEY_ALIAS")?.trim().orEmpty()
    val envKeyPass = System.getenv("KEY_PASSWORD")?.trim().orEmpty()

    if (envPath.isNotEmpty() || envStorePass.isNotEmpty() || envAlias.isNotEmpty()) {
        return validateAndBuildSigningConfig(
            sourceLabel = "CI environment variables (KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD)",
            storeFilePath = envPath,
            storePassword = envStorePass,
            keyAlias = envAlias,
            keyPassword = envKeyPass,
        )
    }

    val keyPropsFile = rootProject.file("key.properties")
    if (!keyPropsFile.exists()) {
        return null
    }

    val props = Properties()
    keyPropsFile.inputStream().use { props.load(it) }
    return validateAndBuildSigningConfig(
        sourceLabel = "${keyPropsFile.absolutePath} (storeFile, storePassword, keyAlias, keyPassword)",
        storeFilePath = props.getProperty("storeFile")?.trim().orEmpty(),
        storePassword = props.getProperty("storePassword")?.trim().orEmpty(),
        keyAlias = props.getProperty("keyAlias")?.trim().orEmpty(),
        keyPassword = props.getProperty("keyPassword")?.trim().orEmpty(),
    )
}

val releaseSigning = loadReleaseSigningConfig()

if (System.getenv("CI") == "true" && releaseSigning == null) {
    gradle.taskGraph.whenReady {
        val runsReleaseTask = allTasks.any { task ->
            task.name.contains("Release") &&
                (task.name.startsWith("assemble") ||
                    task.name.startsWith("bundle") ||
                    task.name.startsWith("package") ||
                    task.name.startsWith("validateSigning"))
        }
        if (runsReleaseTask) {
            throw GradleException(
                "Refusing to build a release APK in CI without a persistent release signing keystore. " +
                    "Configure KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, and KEY_PASSWORD."
            )
        }
    }
}

extensions.configure<ApplicationExtension> {
    namespace = "com.orailnoor.privateagent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.orailnoor.privateagent"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "PrivateAgent"
        manifestPlaceholders["accessibilityLabel"] = "PrivateAgent Screen Control"
    }

    flavorDimensions += "default"

    productFlavors {
        create("stable") {
            dimension = "default"
            applicationId = "com.orailnoor.privateagent"
            manifestPlaceholders["appLabel"] = "PrivateAgent"
            manifestPlaceholders["accessibilityLabel"] = "PrivateAgent Screen Control"
        }
        create("beta") {
            dimension = "default"
            applicationIdSuffix = ".beta"
            manifestPlaceholders["appLabel"] = "PrivateAgent Beta"
            manifestPlaceholders["accessibilityLabel"] = "PrivateAgent Beta Screen Control"
        }
    }

    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = releaseSigning.storeFile
                storePassword = releaseSigning.storePassword
                keyAlias = releaseSigning.keyAlias
                keyPassword = releaseSigning.keyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = if (releaseSigning != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
