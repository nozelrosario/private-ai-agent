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
            for (m in android.javaClass.methods) {
                if (m.name == "setCompileSdk" && m.parameterCount == 1) {
                    try { m.invoke(android, 35) } catch (_: Throwable) {}
                }
                if (m.name == "compileSdkVersion" && m.parameterCount == 1) {
                    try {
                        val pType = m.parameterTypes[0]
                        if (pType == Int::class.javaPrimitiveType || pType == java.lang.Integer::class.java) {
                            m.invoke(android, 35)
                        } else if (pType == String::class.java) {
                            m.invoke(android, "android-35")
                        }
                    } catch (_: Throwable) {}
                }
                if (m.name == "setCompileSdkVersion" && m.parameterCount == 1) {
                    try {
                        val pType = m.parameterTypes[0]
                        if (pType == Int::class.javaPrimitiveType || pType == java.lang.Integer::class.java) {
                            m.invoke(android, 35)
                        } else if (pType == String::class.java) {
                            m.invoke(android, "android-35")
                        }
                    } catch (_: Throwable) {}
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
