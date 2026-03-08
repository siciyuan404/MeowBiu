import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/release.dart';
import '../models/version.dart';
import 'preference_service.dart';

/// 更新服务，负责检查更新、下载和安装APK
class UpdateService {
  static const String _apiUrl = 'https://api.github.com/repos/siciyuan404/MeowBiu/releases';
  static final Dio _dio = Dio();
  static CancelToken? _cancelToken;
  static HttpClient? _httpClient;
  static bool _isCancelled = false;

  /// 检查更新
  /// 
  /// 返回新的发布版本，如果没有更新则返回null
  static Future<Release?> checkForUpdate() async {
    try {
      // 获取偏好设置
      final prefService = PreferenceService();
      await prefService.init();
      final updateChannel = prefService.getUpdateChannel();
      debugPrint('更新频道: ${updateChannel == UpdateChannel.stable ? "稳定版" : "预览版"}');
      
      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionStr = packageInfo.version.split('+')[0]; // 移除构建号部分
      final currentVersion = Version.parse(currentVersionStr);
      debugPrint('当前版本: $currentVersion (原始版本: ${packageInfo.version}, 构建号: ${packageInfo.buildNumber})');
      
      // 获取远程发布列表
      debugPrint('正在从GitHub获取发布信息...');
      final response = await http.get(Uri.parse(_apiUrl));
      if (response.statusCode != 200) {
        throw Exception('获取发布信息失败: ${response.statusCode}');
      }
      debugPrint('成功获取发布信息，状态码: ${response.statusCode}');
      
      // 解析发布列表
      final releases = Release.parseReleases(response.body);
      debugPrint('共获取到 ${releases.length} 个发布版本');
      
      // 输出所有版本
      for (var i = 0; i < releases.length; i++) {
        debugPrint('发布[$i]: ${releases[i].tagName} (预发布: ${releases[i].preRelease})');
      }
      
      // 根据更新频道筛选
      final filteredReleases = updateChannel == UpdateChannel.stable
          ? releases.where((r) => !r.preRelease).toList()
          : releases;
      debugPrint('筛选后还剩 ${filteredReleases.length} 个版本');
      
      // 找到最新版本
      if (filteredReleases.isEmpty) return null;
      final latestRelease = filteredReleases.first;
      debugPrint('最新版本: ${latestRelease.tagName} (${latestRelease.name})');
      
      // 解析版本号并比较
      final latestVersionStr = latestRelease.tagName.replaceFirst('v', '');
      debugPrint('尝试解析版本号: $latestVersionStr');
      final latestVersion = Version.parse(latestVersionStr);
      debugPrint('解析结果: $latestVersion');
      
      // 版本比较
      final comparisonResult = currentVersion.compareTo(latestVersion);
      debugPrint('版本比较结果: $comparisonResult (负数表示有新版本，0表示相同，正数表示本地版本更高)');
      
      // 记录检查时间
      await prefService.setLastCheckUpdateTime(DateTime.now());
      
      // 只有当新版本大于当前版本时才返回
      return comparisonResult < 0 ? latestRelease : null;
    } catch (e) {
      debugPrint('检查更新失败: $e');
      return null;
    }
  }

  /// 下载APK文件
  /// 
  /// [release] 发布信息
  /// [onProgress] 下载进度回调，返回0.0-1.0的进度值
  /// [onError] 错误回调
  /// 返回下载的文件路径，下载失败返回null
  static Future<String?> downloadApk({
    required Release release,
    Function(double)? onProgress,
    Function(String)? onError,
  }) async {
    debugPrint('===== 开始下载APK流程 =====');
    _isCancelled = false;
    
    try {
      // 检查网络状态
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        debugPrint('无网络连接');
        onError?.call('请检查您的网络连接');
        return null;
      }
      
      // 选择下载资源
      final assets = release.assets.where((asset) => asset.isApkFile).toList();
      if (assets.isEmpty) {
        debugPrint('未找到可下载的APK');
        onError?.call('未找到可下载的APK文件');
        return null;
      }
      
      debugPrint('可用APK数量: ${assets.length}个');
      for (var asset in assets) {
        debugPrint('- ${asset.name} (${asset.size} bytes): ${asset.downloadUrl}');
      }
      
      // 简化：直接选择第一个APK (不考虑架构)
      final asset = assets.first;
      debugPrint('将下载: ${asset.name}, 大小: ${asset.size} 字节, URL: ${asset.downloadUrl}');
      
      // 获取应用私有目录（不需要存储权限）
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/${asset.name}';
      debugPrint('下载路径: $filePath');
      
      // 准备文件
      final file = File(filePath);
      if (await file.exists()) {
        debugPrint('删除已存在的文件');
        await file.delete();
      }
      
      // 创建HttpClient
      _httpClient = HttpClient();
      _httpClient!.connectionTimeout = const Duration(seconds: 30);
      
      debugPrint('使用HttpClient下载文件');
      final request = await _httpClient!.getUrl(Uri.parse(asset.downloadUrl));
      
      // 设置请求头
      request.headers.add('Accept', '*/*');
      request.headers.add('User-Agent', 'MiaoWang-App/1.0');
      
      debugPrint('发送HTTP请求...');
      final response = await request.close();
      
      // 检查响应状态
      debugPrint('HTTP响应状态: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('HTTP请求失败: ${response.statusCode}, ${response.reasonPhrase}');
        onError?.call('服务器响应错误: ${response.statusCode}');
        return null;
      }
      
      // 获取总大小
      final totalBytes = response.contentLength;
      debugPrint('开始接收数据，总大小: $totalBytes 字节');
      
      // 创建文件并写入
      final sink = file.openWrite();
      var receivedBytes = 0;
      
      // 接收数据
      final completer = Completer<String?>();
      
      response.listen(
        (bytes) {
          if (_isCancelled) {
            sink.close();
            _httpClient?.close();
            _httpClient = null;
            completer.complete(null);
            return;
          }
          
          sink.add(bytes);
          receivedBytes += bytes.length;
          
          // 报告进度
          if (totalBytes > 0) {
            final progress = receivedBytes / totalBytes;
            debugPrint('已接收: $receivedBytes / $totalBytes (${(progress * 100).toStringAsFixed(1)}%)');
            onProgress?.call(progress);
          }
        },
        onDone: () async {
          // 关闭资源
          await sink.flush();
          await sink.close();
          _httpClient?.close();
          _httpClient = null;
          
          // 检查文件大小
          final fileInfo = await file.stat();
          debugPrint('下载完成，文件大小: ${fileInfo.size}字节');
          
          if (fileInfo.size == 0) {
            debugPrint('错误：下载的文件大小为0');
            onError?.call('下载文件失败：文件大小为0');
            completer.complete(null);
          } else {
            completer.complete(filePath);
          }
        },
        onError: (error) {
          debugPrint('下载过程出错: $error');
          sink.close();
          _httpClient?.close();
          _httpClient = null;
          onError?.call('下载过程出错: $error');
          completer.complete(null);
        },
        cancelOnError: true,
      );
      
      return await completer.future;
    } catch (e, stackTrace) {
      // 详细的错误日志
      debugPrint('下载过程中发生异常: $e');
      debugPrint('===== 堆栈跟踪 =====');
      debugPrint('$stackTrace');
      
      onError?.call('下载失败: ${e.toString()}');
      return null;
    }
  }

  /// 取消当前下载
  static void cancelDownload() {
    debugPrint('取消下载请求');
    _isCancelled = true;
    _cancelToken?.cancel('用户取消下载');
    _cancelToken = null;
    
    if (_httpClient != null) {
      _httpClient!.close(force: true);
      _httpClient = null;
    }
  }

  /// 安装APK
  /// 
  /// [filePath] APK文件路径
  /// 返回是否成功调用安装程序
  static Future<bool> installApk(String filePath) async {
    try {
      debugPrint('准备安装APK: $filePath');
      // Android安装APK
      if (Platform.isAndroid) {
        // 检查文件是否存在
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint('安装失败：APK文件不存在');
          return false;
        }
        
        final fileSize = await file.length();
        debugPrint('APK文件大小: $fileSize 字节');
        
        // 请求安装未知来源应用权限（Android 8.0+需要）
        final status = await Permission.requestInstallPackages.status;
        debugPrint('安装权限状态: $status');
        
        if (!status.isGranted) {
          final result = await Permission.requestInstallPackages.request();
          debugPrint('请求安装权限结果: $result');
          if (!result.isGranted) {
            debugPrint('安装权限被拒绝');
            return false;
          }
        }
        
        // 获取包信息，用于日志
        final packageInfo = await PackageInfo.fromPlatform();
        debugPrint('当前应用信息: 版本=${packageInfo.version}, 构建号=${packageInfo.buildNumber}');
        
        // 使用OpenFile打开APK进行安装
        debugPrint('准备打开APK文件进行安装');
        final result = await OpenFile.open(filePath);
        debugPrint('打开APK结果: ${result.type}, ${result.message}');
        return result.type == ResultType.done;
      } 
      // iOS跳转到App Store
      else if (Platform.isIOS) {
        const appStoreId = '你的App Store ID';
        final url = 'https://apps.apple.com/app/id$appStoreId';
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      
      return false;
    } catch (e, stackTrace) {
      debugPrint('安装APK异常: $e');
      debugPrint('异常堆栈: $stackTrace');
      return false;
    }
  }

  /// 获取最适合当前设备的APK资源
  static ReleaseAsset? _getBestAssetForDevice(List<ReleaseAsset> assets) {
    // 只选择APK文件
    final apkAssets = assets.where((asset) => asset.isApkFile).toList();
    if (apkAssets.isEmpty) return null;
    
    // 获取设备架构信息（简单实现，实际可能需要更复杂的逻辑）
    final preferredArch = _getPreferredArchitecture();
    
    // 寻找匹配架构的APK
    for (final arch in preferredArch) {
      for (final asset in apkAssets) {
        final assetArch = asset.getArchitecture();
        if (assetArch == arch) {
          return asset;
        }
      }
    }
    
    // 如果没有找到匹配架构的APK，返回第一个APK
    return apkAssets.first;
  }

  /// 获取优先架构顺序
  static List<String> _getPreferredArchitecture() {
    // 优先级从高到低排列
    return [
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
      'x86',
    ];
  }
} 