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
    val configureSubproject: (Project) -> Unit = { proj ->
        val android = proj.extensions.findByName("android")
        if (android != null) {
            var currentSdk: Int? = null
            try {
                val getCompileSdk = android.javaClass.methods.find { it.name == "getCompileSdk" && it.parameterCount == 0 }
                currentSdk = getCompileSdk?.invoke(android) as? Int
            } catch (_: Throwable) {}
            if (currentSdk == null) {
                try {
                    val getCompileSdkVersion = android.javaClass.methods.find { it.name == "getCompileSdkVersion" && it.parameterCount == 0 }
                    val sdkStr = getCompileSdkVersion?.invoke(android)?.toString()
                    if (sdkStr != null) {
                        currentSdk = Regex("\\d+").find(sdkStr)?.value?.toIntOrNull()
                    }
                } catch (_: Throwable) {}
            }

            if (currentSdk == null || currentSdk < 34) {
                for (m in android.javaClass.methods) {
                    if (m.name == "setCompileSdk" && m.parameterCount == 1) {
                        try { m.invoke(android, 34) } catch (_: Throwable) {}
                    }
                    if (m.name == "compileSdkVersion" && m.parameterCount == 1) {
                        try {
                            val pType = m.parameterTypes[0]
                            if (pType == Int::class.javaPrimitiveType || pType == java.lang.Integer::class.java) {
                                m.invoke(android, 34)
                            } else if (pType == String::class.java) {
                                m.invoke(android, "android-34")
                            }
                        } catch (_: Throwable) {}
                    }
                    if (m.name == "setCompileSdkVersion" && m.parameterCount == 1) {
                        try {
                            val pType = m.parameterTypes[0]
                            if (pType == Int::class.javaPrimitiveType || pType == java.lang.Integer::class.java) {
                                m.invoke(android, 34)
                            } else if (pType == String::class.java) {
                                m.invoke(android, "android-34")
                            }
                        } catch (_: Throwable) {}
                    }
                }
            }
        }
    }

    if (project.state.executed) {
        configureSubproject(project)
    } else {
        project.afterEvaluate {
            configureSubproject(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
