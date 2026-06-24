import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cat_sound.dart';
import '../models/sound_category.dart';
import '../services/audio_service.dart';
import '../services/storage_service.dart';

// 当前选中的分类提供者
final selectedCategoryProvider = StateProvider<String?>((ref) => null);

// 分类列表提供者
final categoriesProvider = FutureProvider<List<SoundCategory>>((ref) async {
  // 监听soundManagerProvider的状态变化，以便在操作完成后刷新数据
  ref.watch(soundManagerProvider);
  
  final storageService = StorageService();
  await storageService.init();
  return storageService.getAllCategories();
});

// 特定分类下的猫声列表提供者
final categorySoundsProvider = FutureProvider.family<List<CatSound>, String?>((ref, categoryId) async {
  if (categoryId == null) return [];
  
  // 监听soundManagerProvider的状态变化，以便在操作完成后刷新数据
  ref.watch(soundManagerProvider);
  
  final storageService = StorageService();
  await storageService.init();
  return storageService.getSoundsByCategory(categoryId);
});

// 当前播放状态提供者
class PlaybackState {
  final String? playingId;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  
  PlaybackState({
    this.playingId,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
  });
  
  PlaybackState copyWith({
    String? playingId,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
  }) {
    return PlaybackState(
      playingId: playingId ?? this.playingId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

// 播放状态提供者
class PlaybackNotifier extends StateNotifier<PlaybackState> {
  PlaybackNotifier() : super(PlaybackState());

  final AudioService _audioService = AudioService();
  // 保存流订阅,避免泄漏
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  // 取消旧订阅
  void _cancelSubscriptions() {
    _positionSub?.cancel();
    _positionSub = null;
    _durationSub?.cancel();
    _durationSub = null;
  }

  // 添加重置特定音频的状态方法
  void resetState(String soundId) {
    if (state.playingId == soundId) {
      // 完全重置状态，包括进度条、按钮状态和秒数
      _cancelSubscriptions();
      state = PlaybackState(
        playingId: null,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false
      );
    }
  }

  // 播放音频 - 优化响应速度
  Future<void> playSound(CatSound sound) async {
    // 取消上一次的订阅,避免累积
    _cancelSubscriptions();

    // 立即更新UI状态，让界面快速响应
    state = PlaybackState(playingId: sound.id, isPlaying: true);

    // 异步播放音频
    _audioService.safePlay(sound).then((_) {
      if (!mounted) return;
      // 播放成功后再次确认状态
      if (state.playingId == sound.id) {
        state = state.copyWith(isPlaying: true);
      }
    }).catchError((error) {
      if (!mounted) return;
      // 播放失败时重置状态
      if (state.playingId == sound.id) {
        _cancelSubscriptions();
        state = PlaybackState();
      }
      debugPrint('播放音频失败: $error');
    });

    // 监听播放进度
    _positionSub = _audioService.getPositionStream(sound.id).listen((position) {
      if (!mounted) return;
      if (state.playingId == sound.id) {
        state = state.copyWith(position: position);
      }
    });

    // 监听总时长
    _durationSub = _audioService.getDurationStream(sound.id).listen((duration) {
      if (!mounted) return;
      if (state.playingId == sound.id) {
        state = state.copyWith(duration: duration);
      }
    });
  }

  // 暂停播放 - 快速响应
  Future<void> pauseSound() async {
    // 立即更新UI状态
    final currentId = state.playingId;
    if (currentId != null) {
      state = state.copyWith(isPlaying: false);
      // 异步执行暂停操作
      await _audioService.pauseCurrentSound();
    }
  }

  // 停止播放 - 快速响应
  Future<void> stopSound() async {
    // 立即更新UI状态
    _cancelSubscriptions();
    state = PlaybackState();
    // 异步执行停止操作
    await _audioService.stopCurrentSound();
  }

  // 继续播放 - 确保状态正确更新
  Future<void> resumeSound() async {
    // 立即更新UI状态
    final currentId = state.playingId;
    if (currentId != null) {
      // 显式设置isPlaying为true以确保状态更新
      state = state.copyWith(isPlaying: true);

      // 异步执行继续播放操作
      await _audioService.resumeSound();

      // 确保状态在操作完成后仍然正确
      if (!mounted) return;
      if (state.playingId == currentId) {
        state = state.copyWith(isPlaying: true);
      }
    }
  }

  // 清理资源
  @override
  void dispose() {
    _cancelSubscriptions();
    // 注意:AudioService 是全局单例,不应在 Notifier dispose 时销毁
    // 否则 hot reload 或 provider 重建会影响其他使用方
    super.dispose();
  }
}

final playbackProvider = StateNotifierProvider<PlaybackNotifier, PlaybackState>((ref) {
  return PlaybackNotifier();
});

// 音频管理操作提供者
class SoundManagerNotifier extends StateNotifier<AsyncValue<void>> {
  SoundManagerNotifier() : super(const AsyncValue.data(null));
  
  final StorageService _storageService = StorageService();
  final AudioService _audioService = AudioService();
  
  // 添加猫声
  Future<CatSound?> addSound({
    required String name,
    required String audioPath,
    required AudioSourceType sourceType,
    String? categoryId,
  }) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      final sound = await _storageService.addSound(
        name: name,
        audioPath: audioPath,
        sourceType: sourceType,
        categoryId: categoryId,
      );
      
      state = const AsyncValue.data(null);
      return sound;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }
  
  // 更新猫声
  Future<void> updateSound(CatSound sound) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      await _storageService.updateSound(sound);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
  
  // 删除猫声
  Future<void> deleteSound(String soundId) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      final sound = _storageService.getSound(soundId);
      
      if (sound != null) {
        // 清理音频缓存
        await _audioService.clearCache(sound);
        // 从存储中删除
        await _storageService.deleteSound(soundId);
      }
      
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
  
  // 添加分类
  Future<SoundCategory?> addCategory(String name) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      final category = await _storageService.addCategory(name);
      state = const AsyncValue.data(null);
      return category;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }
  
  // 更新分类
  Future<void> updateCategory(SoundCategory category) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      await _storageService.updateCategory(category);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
  
  // 删除分类
  Future<void> deleteCategory(String categoryId) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      await _storageService.deleteCategory(categoryId);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
  
  // 重新排序分类
  Future<void> reorderCategories(List<SoundCategory> newOrder) async {
    state = const AsyncValue.loading();
    
    try {
      await _storageService.init();
      await _storageService.reorderCategories(newOrder);
      state = const AsyncValue.data(null);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
  
  // 清理所有缓存
  Future<bool> clearAllCache() async {
    state = const AsyncValue.loading();
    
    try {
      final result = await _audioService.clearAllCache();
      state = const AsyncValue.data(null);
      return result;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }
  
  // 清理单个猫声缓存
  Future<bool> clearSoundCache(CatSound sound) async {
    state = const AsyncValue.loading();
    
    try {
      final result = await _audioService.clearCache(sound);
      state = const AsyncValue.data(null);
      return result;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return false;
    }
  }
}

final soundManagerProvider = StateNotifierProvider<SoundManagerNotifier, AsyncValue<void>>((ref) {
  return SoundManagerNotifier();
}); 