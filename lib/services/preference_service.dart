import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 更新频道枚举
enum UpdateChannel {
  /// 稳定版
  stable,
  /// 预览版
  preRelease,
}

/// 应用来源枚举
enum AppSource {
  /// GitHub版本
  github,
  /// 应用商店版本
  appStore,
  /// 未知来源
  unknown,
}

/// 偏好设置服务类，管理应用设置
class PreferenceService {
  static final PreferenceService _instance = PreferenceService._internal();
  factory PreferenceService() => _instance;
  PreferenceService._internal();

  static const String _autoUpdateEnabledKey = 'auto_update_enabled';
  static const String _updateChannelKey = 'update_channel';
  static const String _lastCheckUpdateTimeKey = 'last_check_update_time';

  static SharedPreferences? _prefs;
  // 使用 Completer 保证初始化只执行一次,避免并发竞态
  static Completer<void>? _initCompleter;

  /// 初始化
  Future<void> init() async {
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      _prefs = await SharedPreferences.getInstance();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _initCompleter!.future;
  }

  /// 是否启用自动更新
  bool isAutoUpdateEnabled() {
    _ensureInitialized();
    return _prefs?.getBool(_autoUpdateEnabledKey) ?? true; // 默认启用
  }

  /// 设置自动更新状态
  Future<bool> setAutoUpdateEnabled(bool value) async {
    _ensureInitialized();
    return await _prefs!.setBool(_autoUpdateEnabledKey, value);
  }

  /// 获取更新频道
  UpdateChannel getUpdateChannel() {
    _ensureInitialized();
    final channelIndex = _prefs?.getInt(_updateChannelKey) ?? 0;
    return UpdateChannel.values[channelIndex];
  }

  /// 设置更新频道
  Future<bool> setUpdateChannel(UpdateChannel channel) async {
    _ensureInitialized();
    return await _prefs!.setInt(_updateChannelKey, channel.index);
  }

  /// 获取上次检查更新时间
  DateTime? getLastCheckUpdateTime() {
    _ensureInitialized();
    final timestamp = _prefs?.getInt(_lastCheckUpdateTimeKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// 设置上次检查更新时间
  Future<bool> setLastCheckUpdateTime(DateTime dateTime) async {
    _ensureInitialized();
    return await _prefs!.setInt(
      _lastCheckUpdateTimeKey,
      dateTime.millisecondsSinceEpoch,
    );
  }

  /// 检查网络是否可用于下载
  Future<bool> isNetworkAvailableForDownload() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  /// 获取应用安装来源
  Future<AppSource> getAppSource() async {
    // 获取包信息
    final packageInfo = await PackageInfo.fromPlatform();
    
    // 这里根据实际情况判断应用来源
    // 例如，可以根据安装包名后缀或特定标记来区分
    
    // 简单示例：根据包名判断
    if (packageInfo.packageName.endsWith('.playstore')) {
      return AppSource.appStore;
    } else if (packageInfo.packageName.contains('.github')) {
      return AppSource.github;
    }
    
    // 可以添加更多逻辑来精确判断来源
    // 这里简单返回GitHub版本，实际项目中需要更准确的判断
    return AppSource.github;
  }

  /// 判断当前版本是否支持自动更新
  Future<bool> isAutoUpdateSupported() async {
    // 仅GitHub版本支持自动更新
    return await getAppSource() == AppSource.github;
  }

  /// 确保已初始化
  void _ensureInitialized() {
    if (_initCompleter == null || !_initCompleter!.isCompleted) {
      throw StateError('PreferenceService未初始化，请先调用init()方法');
    }
  }
} 