@echo off
echo ===== 开始构建多架构APK (v1.3.4+4) =====
echo.

echo [1/4] 构建arm64-v8a架构APK (现代64位Android手机)...
call flutter build apk --split-per-abi --target-platform android-arm64
if %ERRORLEVEL% neq 0 (
  echo 构建arm64-v8a架构失败!
  exit /b %ERRORLEVEL%
)
echo.

echo [2/4] 构建armeabi-v7a架构APK (32位Android手机)...
call flutter build apk --split-per-abi --target-platform android-arm
if %ERRORLEVEL% neq 0 (
  echo 构建armeabi-v7a架构失败!
  exit /b %ERRORLEVEL%
)
echo.

echo [3/4] 构建x86_64架构APK (64位模拟器)...
call flutter build apk --split-per-abi --target-platform android-x64
if %ERRORLEVEL% neq 0 (
  echo 构建x86_64架构失败!
  exit /b %ERRORLEVEL%
)
echo.

echo [4/4] 构建x86架构APK (32位模拟器)...
call flutter build apk --split-per-abi --target-platform android-x86
if %ERRORLEVEL% neq 0 (
  echo 构建x86架构失败!
  exit /b %ERRORLEVEL%
)
echo.

echo ===== 所有架构APK构建完成! =====

mkdir release-apks 2>nul
cd build\app\outputs\flutter-apk\

echo 重命名并复制APK文件...
copy app-arm64-v8a-release.apk ..\..\..\..\..\release-apks\MeowBiu-v1.3.4-arm64-v8a.apk
copy app-armeabi-v7a-release.apk ..\..\..\..\..\release-apks\MeowBiu-v1.3.4-armeabi-v7a.apk
copy app-x86_64-release.apk ..\..\..\..\..\release-apks\MeowBiu-v1.3.4-x86_64.apk
copy app-x86-release.apk ..\..\..\..\..\release-apks\MeowBiu-v1.3.4-x86.apk
cd ..\..\..\..

echo.
echo 文件已保存到 release-apks 目录:
echo - MeowBiu-v1.3.4-arm64-v8a.apk
echo - MeowBiu-v1.3.4-armeabi-v7a.apk
echo - MeowBiu-v1.3.4-x86_64.apk
echo - MeowBiu-v1.3.4-x86.apk
echo.
echo 构建完成! 