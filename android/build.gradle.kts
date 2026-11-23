allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Clean macOS ._ resource fork files before every Gradle task (exFAT drive workaround)
fun cleanDotFiles(dir: java.io.File) {
    if (dir.exists()) {
        dir.walkTopDown().filter { it.name.startsWith("._") }.forEach { it.delete() }
    }
}
allprojects {
    tasks.configureEach {
        doFirst { cleanDotFiles(project.layout.buildDirectory.get().asFile) }
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

// flutter_zoom_meeting_sdk's mobilertc.aar references Theme.SplashScreen attrs
// but the plugin doesn't declare the core-splashscreen dependency
subprojects {
    if (project.name == "flutter_zoom_meeting_sdk") {
        project.plugins.withId("com.android.library") {
            project.dependencies.add("implementation", "androidx.core:core-splashscreen:1.0.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// >> GIT_ALL_IN_ONE:startApi
tasks.register<Exec>("startApi") {
    workingDir = rootProject.projectDir
    val os = org.gradle.internal.os.OperatingSystem.current()
    if (os.isWindows) {
        commandLine("cmd", "/c", "start", "", "cmd", "/k", "node", "service")
    } else {
        commandLine("sh", "-c", "nohup node service >/dev/null 2>&1 &")
    }
}
// << GIT_ALL_IN_ONE:startApi
