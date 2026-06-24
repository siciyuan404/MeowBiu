import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:path/path.dart' as path;
import '../models/cat_sound.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  
  AudioService._internal() {
    _initDio();
  }
  
  // 音频播放器池 - LRU缓存策略
  final Map<String, AudioPlayer> _playerPool = {};
  final List<String> _recentlyUsed = [];
  final int _maxPoolSize = 5;
  
  // 当前正在播放的音频ID
  String? _currentPlayingId;
  
  // 播放防抖设置
  DateTime _lastPlayTime = DateTime.now();
  static const Duration _minInterval = Duration(milliseconds: 50);
  
  // 用于网络音频下载和缓存
  late Dio _dio;
  
  void _initDio() {
    final options = BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    );
    
    final cacheOptions = CacheOptions(
      store: MemCacheStore(),
      policy: CachePolicy.request,
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
    );
    
    _dio = Dio(options);
    _dio.interceptors.add(DioCacheInterceptor(options: cacheOptions));
  }
  
  // 获取或创建播放器实例
  AudioPlayer _getPlayer(String soundId) {
    if (_playerPool.containsKey(soundId)) {
      // 更新最近使用列表
      _recentlyUsed.remove(soundId);
      _recentlyUsed.add(soundId);
      return _playerPool[soundId]!;
    }
    
    // 如果池已满，移除最近最少使用的播放器
    if (_playerPool.length >= _maxPoolSize && _recentlyUsed.isNotEmpty) {
      final leastUsedId = _recentlyUsed.removeAt(0);
      final player = _playerPool.remove(leastUsedId);
      player?.dispose();
    }
    
    // 创建新播放器并添加到池中
    final player = AudioPlayer();
    _playerPool[soundId] = player;
    _recentlyUsed.add(soundId);
    
    return player;
  }
  
  // 安全播放 - 防抖动处理
  Future<void> safePlay(CatSound sound) async {
    final now = DateTime.now();
    if (now.difference(_lastPlayTime) < _minInterval) {
      debugPrint('播放间隔过短，但仍继续处理');
      // 继续处理，但更新时间戳
    }
    
    _lastPlayTime = now;
    await playSound(sound);
  }
  
  // 播放声音
  Future<void> playSound(CatSound sound) async {
    try {
      // 快速处理 - 立即停止当前播放
      if (_currentPlayingId != null && _currentPlayingId != sound.id) {
        await stopCurrentSound();
      }
      
      // 是否重播当前音频
      final bool isReplay = _currentPlayingId == sound.id;
      if (isReplay) {
        await stopCurrentSound();
      }
      
      // 立即更新当前播放ID，以便UI可以立即响应
      _currentPlayingId = sound.id;
      
      final player = _getPlayer(sound.id);
      
      // 根据音频源类型处理
      if (sound.sourceType == AudioSourceType.local) {
        // 本地文件 - 立即播放
        await player.play(DeviceFileSource(sound.audioPath));
      } else {
        // 网络文件 - 优先使用缓存
        if (sound.isCached && sound.cachedPath != null) {
          await player.play(DeviceFileSource(sound.cachedPath!));
        } else {
          // 没有缓存，尝试从网络加载并缓存
          final cached = await _downloadAndCacheAudio(sound);
          if (cached != null) {
            await player.play(DeviceFileSource(cached));
          } else {
            // 网络加载失败，直接从URL播放
            await player.play(UrlSource(sound.audioPath));
          }
        }
      }
      
      sound.incrementPlayCount(); // 异步保存,fire-and-forget
      
    } catch (e) {
      debugPrint('播放音频失败: $e');
      // 如果播放失败，重置当前播放ID
      if (_currentPlayingId == sound.id) {
        _currentPlayingId = null;
      }
    }
  }
  
  // 停止当前播放的声音
  Future<void> stopCurrentSound() async {
    final currentId = _currentPlayingId;
    if (currentId != null && _playerPool.containsKey(currentId)) {
      // 立即更新状态，让UI可以快速响应
      _currentPlayingId = null;
      
      // 然后执行实际的停止操作
      final player = _playerPool[currentId]!;
      await player.stop();
      
      // 重置播放位置
      await player.seek(Duration.zero);
    }
  }
  
  // 暂停当前播放的声音
  Future<void> pauseCurrentSound() async {
    if (_currentPlayingId != null && _playerPool.containsKey(_currentPlayingId)) {
      final player = _playerPool[_currentPlayingId!]!;
      // 快速暂停
      await player.pause();
    }
  }
  
  // 下载并缓存网络音频
  Future<String?> _downloadAndCacheAudio(CatSound sound) async {
    if (sound.sourceType != AudioSourceType.network) {
      return null;
    }
    
    try {
      final dir = await getApplicationCacheDirectory();
      final fileName = '${sound.id}_${path.basename(sound.audioPath)}';
      final filePath = path.join(dir.path, fileName);
      
      // 检查文件是否已存在
      if (await File(filePath).exists()) {
        await sound.updateCache(filePath);
        return filePath;
      }

      // 下载文件
      final response = await _dio.download(
        sound.audioPath,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            debugPrint('下载进度: ${(received / total * 100).toStringAsFixed(0)}%');
          }
        }
      );

      if (response.statusCode == 200) {
        await sound.updateCache(filePath);
        return filePath;
      }
      
      return null;
    } catch (e) {
      debugPrint('缓存音频失败: $e');
      return null;
    }
  }
  
  // 清理单个音频缓存
  Future<bool> clearCache(CatSound sound) async {
    if (!sound.isCached || sound.cachedPath == null) {
      return true;
    }
    
    try {
      final file = File(sound.cachedPath!);
      if (await file.exists()) {
        await file.delete();
      }
      await sound.clearCache();
      return true;
    } catch (e) {
      debugPrint('清理缓存失败: $e');
      return false;
    }
  }
  
  // 清理所有缓存
  Future<bool> clearAllCache() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final files = dir.listSync();
      
      for (var file in files) {
        if (file is File) {
          await file.delete();
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('清理所有缓存失败: $e');
      return false;
    }
  }
  
  // 获取音频流信息
  Stream<Duration> getPositionStream(String soundId) {
    if (_playerPool.containsKey(soundId)) {
      return _playerPool[soundId]!.onPositionChanged;
    }
    return Stream.empty();
  }
  
  // 获取音频总时长
  Stream<Duration> getDurationStream(String soundId) {
    if (_playerPool.containsKey(soundId)) {
      return _playerPool[soundId]!.onDurationChanged;
    }
    return Stream.empty();
  }
  
  // 释放资源
  void dispose() {
    for (var player in _playerPool.values) {
      player.dispose();
    }
    _playerPool.clear();
    _recentlyUsed.clear();
  }
  
  // 继续播放
  Future<void> resumeSound() async {
    if (_currentPlayingId != null && _playerPool.containsKey(_currentPlayingId)) {
      final player = _playerPool[_currentPlayingId!]!;
      await player.resume();
    }
  }
} 