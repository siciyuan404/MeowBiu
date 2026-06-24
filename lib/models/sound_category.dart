import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

part 'sound_category.g.dart';

@HiveType(typeId: 1)
class SoundCategory extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  List<String> soundIds;

  @HiveField(3)
  int order;

  SoundCategory({
    required this.id,
    required this.name,
    List<String>? soundIds,
    this.order = 0,
  }) : soundIds = soundIds ?? [];

  Future<void> addSound(String soundId) async {
    if (!soundIds.contains(soundId)) {
      soundIds.add(soundId);
      await save();
    }
  }

  Future<void> removeSound(String soundId) async {
    soundIds.remove(soundId);
    await save();
  }

  Future<void> reorderSounds(List<String> newOrder) async {
    assert(newOrder.length == soundIds.length, '新排序列表长度必须与原列表相同');
    assert(newOrder.toSet().length == soundIds.length, '新排序列表不能有重复元素');
    
    soundIds = newOrder;
    await save();
  }
} 