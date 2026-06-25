# Flutter path_provider 使用 Pigeon 生成代码,需要保留相关类
# 否则 release 构建中 R8 会剥离 Pigeon 生成的 PathProviderApi 类
# 导致 "No JNI instance is available" 错误

# 保留 path_provider_android 插件所有类
-keep class io.flutter.plugins.pathprovider.** { *; }

# 保留 Pigeon 生成的 path_provider 相关类
-keep class dev.flutter.pigeon.path_provider_android.** { *; }

# 保留所有 Pigeon 生成的类(其他插件也可能使用 Pigeon)
-keep class dev.flutter.pigeon.** { *; }

# 保留 Flutter 引擎相关类
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 保留 shared_preferences 插件
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# 保留 package_info_plus 插件
-keep class dev.britannia.in_app_info.** { *; }
-keep class io.flutter.plugins.packageinfo.** { *; }

# 保留 connectivity_plus 插件
-keep class dev.britannia.connectivity_plus.** { *; }

# 保留 permission_handler 插件
-keep class com.baseflow.permissionhandler.** { *; }

# 保留 audioplayers 插件
-keep class xyz.luan.audioplayers.** { *; }

# 保留 just_audio 插件
-keep class com.ryanheise.just_audio.** { *; }

# 保留 url_launcher 插件
-keep class io.flutter.plugins.urllauncher.** { *; }

# 保留 ffmpeg_kit_flutter 插件
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.ffmpegkit_flutter.** { *; }

# 保留 file_selector 插件
-keep class io.flutter.plugins.fileselector.** { *; }

# 保留 open_file 插件
-keep class com.llf.openfile.** { *; }
