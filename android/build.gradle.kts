allprojects {
    repositories {
        // 国内镜像加速，拉取失败时回退到官方源
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/central")
        google()
        mavenCentral()
    }
}

// 修复 ffmpeg_kit_flutter 等插件的 namespace 问题
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.findByName("android")
            if (android is com.android.build.gradle.LibraryExtension) {
                if (android.namespace == null || android.namespace.isNullOrEmpty()) {
                    // 从 AndroidManifest.xml 中提取 package 属性作为 namespace
                    val manifestFile = file("${project.projectDir}/src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestContent = manifestFile.readText()
                        val packageMatch = Regex("""package="([^"]+)"""").find(manifestContent)
                        if (packageMatch != null) {
                            android.namespace = packageMatch.groupValues[1]
                        }
                    }
                }
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
