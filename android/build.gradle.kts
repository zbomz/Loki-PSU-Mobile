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
    // Provide `flutter` SDK version properties to plugin subprojects whose
    // Groovy build.gradle references `flutter.compileSdkVersion`, etc.
    // These properties are normally only available on the :app module.
    // Exclude :app itself — it gets the real Flutter extension from the plugin.
    if (project.name != "app") {
        project.ext.set("flutter", mapOf(
            "compileSdkVersion" to 34,
            "targetSdkVersion" to 34,
            "minSdkVersion" to 21,
            "ndkVersion" to "25.1.8937393"
        ))
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
