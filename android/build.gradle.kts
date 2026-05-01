allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = project.layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        if (project.extensions.findByName("android") != null) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileSdkVersion(37)
            }
        }
    }
}

/*
subprojects {
    if (project.path != ":app") {
        evaluationDependsOn(":app")
    }
}
*/

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
