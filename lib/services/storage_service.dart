import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/cat_sound.dart';
import '../models/sound_category.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  
  StorageService._internal();
  
  static const String _soundsBoxName = 'cat_sounds';
  static const String _categoriesBoxName = 'sound_categories';
  
  late Box<CatSound> _soundsBox;
  late Box<SoundCategory> _categoriesBox;
  
  bool _isInitialized = false;
  // 使用 Completer 保证初始化只执行一次,避免并发竞态
  Completer<void>? _initCompleter;
  final Uuid _uuid = const Uuid();

  // 初始化Hive数据库
  Future<void> init() async {
    if (_isInitialized) return;
    // 如果正在初始化,等待完成
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();

    try {
      // 初始化Hive
      // path_provider 的平台通道在应用启动早期可能尚未就绪,重试几次以提高健壮性
      final appDocDir = await _withRetry(
        () => getApplicationDocumentsDirectory(),
        maxAttempts: 5,
        delay: const Duration(milliseconds: 500),
      );
      await Hive.initFlutter(appDocDir.path);

      // 注册适配器
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(CatSoundAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(SoundCategoryAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(AudioSourceTypeAdapter());
      }

      // 打开盒子,若数据损坏则尝试删除后重建
      _soundsBox = await _openBoxSafely<CatSound>(_soundsBoxName);
      _categoriesBox =
          await _openBoxSafely<SoundCategory>(_categoriesBoxName);

      // 检查并初始化默认数据
      await _initDefaultData();

      _isInitialized = true;
      _initCompleter!.complete();
      debugPrint('存储服务初始化成功');
    } catch (e, stack) {
      debugPrint('存储服务初始化失败: $e\n$stack');
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  // 带重试的异步操作
  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    required int maxAttempts,
    required Duration delay,
  }) async {
    int attempt = 0;
    dynamic lastError;
    while (attempt < maxAttempts) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        attempt++;
        debugPrint('操作失败(第 $attempt/$maxAttempts 次): $e');
        if (attempt < maxAttempts) {
          await Future.delayed(delay);
        }
      }
    }
    throw lastError;
  }

  // 安全打开 Hive Box,若打开失败(数据损坏等)则删除后重建
  Future<Box<T>> _openBoxSafely<T>(String name) async {
    try {
      return await Hive.openBox<T>(name);
    } catch (e) {
      debugPrint('打开 Box($name) 失败,尝试清理后重建: $e');
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (deleteError) {
        debugPrint('清理 Box($name) 磁盘文件失败: $deleteError');
        // 即使删除失败也尝试打开,可能文件已损坏但 Hive 能处理
      }
      return await Hive.openBox<T>(name);
    }
  }
  
  // 初始化默认数据
  Future<void> _initDefaultData() async {
    // 如果分类为空，创建默认分类
    if (_categoriesBox.isEmpty) {
      final defaultCategories = [
        SoundCategory(id: _uuid.v4(), name: '求救', order: 0),
        SoundCategory(id: _uuid.v4(), name: '吃饭', order: 1),
        SoundCategory(id: _uuid.v4(), name: '伙伴', order: 2),
      ];
      
      for (var category in defaultCategories) {
        await _categoriesBox.put(category.id, category);
      }
    }
  }
  
  // 获取所有猫声
  List<CatSound> getAllSounds() {
    return _soundsBox.values.toList();
  }
  
  // 获取特定分类的猫声
  List<CatSound> getSoundsByCategory(String categoryId) {
    final category = _categoriesBox.get(categoryId);
    if (category == null) return [];
    
    return category.soundIds
        .map((id) => _soundsBox.get(id))
        .whereType<CatSound>()
        .toList();
  }
  
  // 获取所有分类
  List<SoundCategory> getAllCategories() {
    // 按order排序
    final categories = _categoriesBox.values.toList();
    categories.sort((a, b) => a.order.compareTo(b.order));
    return categories;
  }
  
  // 添加新猫声
  Future<CatSound> addSound({
    required String name,
    required String audioPath,
    required AudioSourceType sourceType,
    String? categoryId,
  }) async {
    final sound = CatSound(
      id: _uuid.v4(),
      name: name,
      audioPath: audioPath,
      sourceType: sourceType,
    );
    
    await _soundsBox.put(sound.id, sound);
    
    // 如果指定了分类，将猫声添加到分类中
    if (categoryId != null) {
      final category = _categoriesBox.get(categoryId);
      if (category != null) {
        await category.addSound(sound.id);
      }
    }
    
    return sound;
  }
  
  // 更新猫声
  Future<void> updateSound(CatSound sound) async {
    await _soundsBox.put(sound.id, sound);
  }
  
  // 删除猫声
  Future<void> deleteSound(String soundId) async {
    // 先删除猫声本身
    await _soundsBox.delete(soundId);
    // 再从所有分类中移除引用,避免孤儿引用
    for (var category in _categoriesBox.values) {
      if (category.soundIds.contains(soundId)) {
        await category.removeSound(soundId);
      }
    }
  }
  
  // 添加新分类
  Future<SoundCategory> addCategory(String name) async {
    // 获取当前最大order
    int maxOrder = 0;
    if (_categoriesBox.isNotEmpty) {
      maxOrder = _categoriesBox.values
          .map((c) => c.order)
          .reduce((a, b) => a > b ? a : b);
    }
    
    final category = SoundCategory(
      id: _uuid.v4(),
      name: name,
      order: maxOrder + 1,
    );
    
    await _categoriesBox.put(category.id, category);
    return category;
  }
  
  // 更新分类
  Future<void> updateCategory(SoundCategory category) async {
    await _categoriesBox.put(category.id, category);
  }
  
  // 删除分类及其关联的猫声(与 UI 提示一致)
  Future<void> deleteCategory(String categoryId) async {
    final category = _categoriesBox.get(categoryId);
    if (category == null) return;

    // 先删除该分类下的所有猫声
    for (final soundId in category.soundIds.toList()) {
      await _soundsBox.delete(soundId);
    }

    // 再删除分类本身
    await _categoriesBox.delete(categoryId);
  }
  
  // 重新排序分类
  Future<void> reorderCategories(List<SoundCategory> newOrder) async {
    // 更新所有分类的order
    for (int i = 0; i < newOrder.length; i++) {
      final category = newOrder[i];
      category.order = i;
      await _categoriesBox.put(category.id, category);
    }
  }
  
  // 获取猫声
  CatSound? getSound(String soundId) {
    return _soundsBox.get(soundId);
  }
  
  // 获取分类
  SoundCategory? getCategory(String categoryId) {
    return _categoriesBox.get(categoryId);
  }
  
  // 关闭存储
  Future<void> close() async {
    await _soundsBox.close();
    await _categoriesBox.close();
    _isInitialized = false;
  }
} 