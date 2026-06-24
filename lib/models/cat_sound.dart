import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

part 'cat_sound.g.dart';

enum AudioSourceType {
  local,
  network,
}

@HiveType(typeId: 0)
class CatSound extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String audioPath;

  @HiveField(3)
  AudioSourceType sourceType;

  @HiveField(4)
  String? cachedPath;

  @HiveField(5)
  int playCount;

  @HiveField(6)
  DateTime lastPlayed;

  @HiveField(7, defaultValue: false)
  bool isFavorite;

  @HiveField(8)
  int? durationMs;

  CatSound({
    required this.id,
    required this.name,
    required this.audioPath,
    required this.sourceType,
    this.cachedPath,
    this.playCount = 0,
    DateTime? lastPlayed,
    this.isFavorite = false,
    this.durationMs,
  }) : lastPlayed = lastPlayed ?? DateTime.now();

  bool get isNetworkSource => sourceType == AudioSourceType.network;
  bool get isCached => cachedPath != null;

  Duration get duration => Duration(milliseconds: durationMs ?? 0);

  // 安全保存,避免未 await 导致内存与磁盘不一致
  Future<void> _safeSave() async {
    try {
      await save();
    } catch (e) {
      debugPrint('CatSound 保存失败: $e');
    }
  }

  Future<void> incrementPlayCount() async {
    playCount++;
    lastPlayed = DateTime.now();
    await _safeSave();
  }

  Future<void> updateCache(String path) async {
    cachedPath = path;
    await _safeSave();
  }

  Future<void> clearCache() async {
    cachedPath = null;
    await _safeSave();
  }

  Future<void> toggleFavorite() async {
    isFavorite = !isFavorite;
    await _safeSave();
  }

  Future<void> updateDuration(Duration duration) async {
    durationMs = duration.inMilliseconds;
    await _safeSave();
  }
}

// 音频源类型适配器
class AudioSourceTypeAdapter extends TypeAdapter<AudioSourceType> {
  @override
  final int typeId = 2;
  
  @override
  AudioSourceType read(BinaryReader reader) {
    return AudioSourceType.values[reader.readInt()];
  }
  
  @override
  void write(BinaryWriter writer, AudioSourceType obj) {
    writer.writeInt(obj.index);
  }
} 