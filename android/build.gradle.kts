allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val getCompileSdk = android.javaClass.methods.find { it.name == "getCompileSdk" && it.parameterCount == 0 }
                val currentSdk = getCompileSdk?.invoke(android) as? Int
                if (currentSdk == null || currentSdk < 35) {
                    val setCompileSdk = android.javaClass.methods.find { it.name == "setCompileSdk" && it.parameterCount == 1 }
                    setCompileSdk?.invoke(android, 35)
                }
            } catch (_: Throwable) {}
            try {
                val setCompileSdkVersion = android.javaClass.methods.find { it.name == "setCompileSdkVersion" && it.parameterCount == 1 }
                if (setCompileSdkVersion != null) {
                    val pType = setCompileSdkVersion.parameterTypes[0]
                    if (pType == Int::class.javaPrimitiveType || pType == java.lang.Integer::class.java) {
                        setCompileSdkVersion.invoke(android, 35)
                    }
                }
            } catch (_: Throwable) {}
        }
    }

    tasks.matching { it.name.contains("check") && it.name.contains("AarMetadata") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
