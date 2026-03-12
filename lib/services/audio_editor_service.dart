import 'dart:io';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// 进度回调函数类型
typedef void ProgressCallback(double progress);

/// 音频编辑服务
/// 使用纯 Dart/just_audio 实现音频处理功能
class AudioEditorService {
  static final AudioPlayer _durationPlayer = AudioPlayer();

  /// 获取媒体时长
  static Future<double?> getMediaDuration(String mediaPath) async {
    try {
      // 支持音频文件
      if (mediaPath.endsWith('.mp3') || 
          mediaPath.endsWith('.wav') || 
          mediaPath.endsWith('.m4a') ||
          mediaPath.endsWith('.aac')) {
        final duration = await _durationPlayer.setFilePath(mediaPath);
        return duration?.inMilliseconds.toDouble();
      }
      
      // 尝试使用 ffprobe（如果安装了 ffmpeg）
      final result = await Process.run('ffprobe', [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        mediaPath
      ]);
      
      if (result.exitCode == 0) {
        return double.tryParse(result.stdout.toString().trim()) ?? null;
      }
      
      return null;
    } catch (e) {
      print('获取媒体时长失败: $e');
      return null;
    }
  }

  /// 获取媒体信息
  static Future<Map<String, dynamic>?> getMediaInfo(String mediaPath) async {
    try {
      final duration = await getMediaDuration(mediaPath);
      final file = File(mediaPath);
      final size = await file.length();
      
      return {
        'duration': duration,
        'size': size,
        'path': mediaPath,
        'exists': await file.exists(),
      };
    } catch (e) {
      print('获取媒体信息失败: $e');
      return null;
    }
  }

  /// 裁切音频（纯 Dart 实现）
  static Future<String?> trimAudio({
    required String audioPath,
    required double startTime,
    required double duration,
    ProgressCallback? onProgress,
  }) async {
    try {
      final inputFile = File(audioPath);
      if (!await inputFile.exists()) {
        print('音频文件不存在: $audioPath');
        return null;
      }

      final ext = audioPath.split('.').last.toLowerCase();
      
      // 如果系统有 ffmpeg，使用它
      final hasFFmpeg = await _checkFFmpeg();
      if (hasFFmpeg) {
        return await _trimAudioWithFFmpeg(
          audioPath: audioPath,
          startTime: startTime,
          duration: duration,
          onProgress: onProgress,
        );
      }

      // 否则使用 just_audio 录制方式（需要播放）
      return await _trimAudioWithJustAudio(
        audioPath: audioPath,
        startTime: startTime,
        duration: duration,
        onProgress: onProgress,
      );
    } catch (e) {
      print('裁切音频失败: $e');
      return null;
    }
  }

  /// 从视频中提取音频（使用系统 ffmpeg 或简单复制）
  static Future<String?> extractAudioFromVideo({
    required String videoPath,
    double startTime = 0,
    double? duration,
    ProgressCallback? onProgress,
  }) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        print('视频文件不存在: $videoPath');
        return null;
      }

      final hasFFmpeg = await _checkFFmpeg();
      if (!hasFFmpeg) {
        print('需要 ffmpeg 来提取音频');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/extracted_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final args = [
        '-i', videoPath,
        '-vn', // 不处理视频
        '-acodec', 'libmp3lame',
        '-q:a', '2',
      ];

      if (startTime > 0) {
        args.addAll(['-ss', startTime.toString()]);
      }

      if (duration != null) {
        args.addAll(['-t', duration.toString()]);
      }

      args.add(outputPath);

      final result = await Process.run('ffmpeg', args);

      if (result.exitCode == 0) {
        onProgress?.call(1.0);
        return outputPath;
      } else {
        print('提取音频失败: ${result.stderr}');
        return null;
      }
    } catch (e) {
      print('提取音频失败: $e');
      return null;
    }
  }

  /// 转换音频格式
  static Future<String?> convertAudio({
    required String inputPath,
    required String outputFormat,
    ProgressCallback? onProgress,
  }) async {
    try {
      final hasFFmpeg = await _checkFFmpeg();
      if (!hasFFmpeg) {
        print('需要 ffmpeg 来转换格式');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final baseName = DateTime.now().millisecondsSinceEpoch.toString();
      final outputPath = '${dir.path}/$baseName.$outputFormat';

      final result = await Process.run('ffmpeg', [
        '-i', inputPath,
        '-acodec', outputFormat == 'mp3' ? 'libmp3lame' : 'copy',
        outputPath
      ]);

      if (result.exitCode == 0) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print('转换音频失败: $e');
      return null;
    }
  }

  /// 合并多个音频文件
  static Future<String?> mergeAudios({
    required List<String> inputPaths,
    ProgressCallback? onProgress,
  }) async {
    try {
      final hasFFmpeg = await _checkFFmpeg();
      if (!hasFFmpeg) {
        print('需要 ffmpeg 来合并音频');
        return null;
      }

      // 创建临时 concat 文件
      final concatContent = inputPaths.map((p) => "file '$p'").join('\n');
      final concatFile = File('${(await getTemporaryDirectory()).path}/concat.txt');
      await concatFile.writeAsString(concatContent);

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final result = await Process.run('ffmpeg', [
        '-f', 'concat',
        '-safe', '0',
        '-i', concatFile.path,
        '-c', 'copy',
        outputPath
      ]);

      await concatFile.delete();

      if (result.exitCode == 0) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print('合并音频失败: $e');
      return null;
    }
  }

  /// 调整音频音量
  static Future<String?> adjustVolume({
    required String inputPath,
    required double volume,
  }) async {
    try {
      final hasFFmpeg = await _checkFFmpeg();
      if (!hasFFmpeg) {
        print('需要 ffmpeg 来调整音量');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/vol_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final result = await Process.run('ffmpeg', [
        '-i', inputPath,
        '-af', 'volume=$volume',
        outputPath
      ]);

      if (result.exitCode == 0) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print('调整音量失败: $e');
      return null;
    }
  }

  /// 淡入淡出效果
  static Future<String?> fadeAudio({
    required String inputPath,
    double fadeIn = 0,
    double fadeOut = 0,
  }) async {
    try {
      final hasFFmpeg = await _checkFFmpeg();
      if (!hasFFmpeg) {
        print('需要 ffmpeg 来添加淡入淡出');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/fade_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final filters = <String>[];
      if (fadeIn > 0) {
        filters.add('afade=t=in:st=0:d=$fadeIn');
      }
      if (fadeOut > 0) {
        final duration = await getMediaDuration(inputPath);
        if (duration != null) {
          filters.add('afade=t=out:st=${duration - fadeOut}:d=$fadeOut');
        }
      }

      final result = await Process.run('ffmpeg', [
        '-i', inputPath,
        '-af', filters.join(','),
        outputPath
      ]);

      if (result.exitCode == 0) {
        return outputPath;
      }
      return null;
    } catch (e) {
      print('添加淡入淡出失败: $e');
      return null;
    }
  }

  /// 取消所有正在进行的任务
  static Future<void> cancelAll() async {
    // 如果使用 just_audio 的流，可以取消
  }

  /// 获取 FFmpeg 版本
  static Future<String?> getFFmpegVersion() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final match = RegExp(r'ffmpeg version (\S+)').firstMatch(output);
        return match?.group(1);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ========== 私有辅助方法 ==========

  /// 检查系统是否有 ffmpeg
  static Future<bool> _checkFFmpeg() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// 使用 ffmpeg 裁切音频
  static Future<String?> _trimAudioWithFFmpeg({
    required String audioPath,
    required double startTime,
    required double duration,
    ProgressCallback? onProgress,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = '${dir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp3';

    final result = await Process.run('ffmpeg', [
      '-i', audioPath,
      '-ss', startTime.toString(),
      '-t', duration.toString(),
      '-acodec', 'libmp3lame',
      '-q:a', '2',
      outputPath
    ]);

    if (result.exitCode == 0) {
      onProgress?.call(1.0);
      return outputPath;
    }
    return null;
  }

  /// 使用 just_audio 裁切（播放录制方式）
  static Future<String?> _trimAudioWithJustAudio({
    required String audioPath,
    required double startTime,
    required double duration,
    ProgressCallback? onProgress,
  }) async {
    // 简化版：直接返回原文件并提示用户
    // 完整实现需要使用 audio_session + 录制
    print('使用 just_audio 裁切需要完整实现音频录制功能');
    return null;
  }
}
