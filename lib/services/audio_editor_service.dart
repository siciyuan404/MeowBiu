import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// 进度回调函数类型
typedef void ProgressCallback(double progress);

/// 音频编辑服务
/// 使用 ffmpeg_kit_flutter_audio_min 实现音频处理功能
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
      
      // 对于视频文件，使用 ffprobe
      final session = await FFmpegKit.execute(
        '-i "$mediaPath" -hide_banner -f null -'
      );
      final output = await session.getOutput();
      
      // 解析时长，格式: Duration: 00:01:23.45
      final durationMatch = RegExp(r'Duration:\s*(\d{2}):(\d{2}):(\d{2})\.(\d{2})').firstMatch(output ?? '');
      if (durationMatch != null) {
        final hours = int.parse(durationMatch.group(1)!);
        final minutes = int.parse(durationMatch.group(2)!);
        final seconds = int.parse(durationMatch.group(3)!);
        final centiseconds = int.parse(durationMatch.group(4)!);
        return (hours * 3600 + minutes * 60 + seconds + centiseconds / 100) * 1000;
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

  /// 裁切音频
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

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp3';

      // 使用 FFmpegKit 裁切音频
      // -ss: 开始时间(秒), -t: 持续时间(秒), -c:a: 音频编码器
      final args = [
        '-i', audioPath,
        '-ss', startTime.toString(),
        '-t', duration.toString(),
        '-c:a', 'libmp3lame',
        '-q:a', '2',
        outputPath,
      ];
      
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
        return outputPath;
      } else {
        final output = await session.getOutput();
        print('裁切音频失败: $output');
        return null;
      }
    } catch (e) {
      print('裁切音频失败: $e');
      return null;
    }
  }

  /// 从视频中提取音频
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

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/extracted_${DateTime.now().millisecondsSinceEpoch}.mp3';

      // 构建 FFmpeg 命令
      final List<String> args = ['-i', videoPath];
      
      if (startTime > 0) {
        args.addAll(['-ss', startTime.toString()]);
      }

      if (duration != null) {
        args.addAll(['-t', duration.toString()]);
      }

      args.addAll([
        '-vn', // 不处理视频
        '-c:a', 'libmp3lame',
        '-q:a', '2',
        outputPath,
      ]);

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
        return outputPath;
      } else {
        final output = await session.getOutput();
        print('提取音频失败: $output');
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
      final dir = await getApplicationDocumentsDirectory();
      final baseName = DateTime.now().millisecondsSinceEpoch.toString();
      final outputPath = '${dir.path}/$baseName.$outputFormat';

      List<String> args;
      if (outputFormat == 'mp3') {
        args = ['-i', inputPath, '-c:a', 'libmp3lame', outputPath];
      } else {
        args = ['-i', inputPath, '-c:a', 'copy', outputPath];
      }

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
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
      // 创建临时 concat 文件
      final concatContent = inputPaths.map((p) => "file '$p'").join('\n');
      final tempDir = await getTemporaryDirectory();
      final concatFile = File('${tempDir.path}/concat.txt');
      await concatFile.writeAsString(concatContent);

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final args = [
        '-f', 'concat',
        '-safe', '0',
        '-i', concatFile.path,
        '-c', 'copy',
        outputPath,
      ];
      
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      await concatFile.delete();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
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
    ProgressCallback? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/vol_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final args = [
        '-i', inputPath,
        '-af', 'volume=$volume',
        outputPath,
      ];
      
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
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
    ProgressCallback? onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/fade_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final filters = <String>[];
      if (fadeIn > 0) {
        filters.add('afade=t=in:st=0:d=$fadeIn');
      }
      if (fadeOut > 0) {
        final duration = await getMediaDuration(inputPath);
        if (duration != null) {
          final durationSec = duration / 1000;
          filters.add('afade=t=out:st=${durationSec - fadeOut}:d=$fadeOut');
        }
      }

      final args = [
        '-i', inputPath,
        '-af', filters.join(','),
        outputPath,
      ];
      
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
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
    await FFmpegKit.cancel();
  }

  /// 获取 FFmpeg 版本
  static Future<String?> getFFmpegVersion() async {
    try {
      final session = await FFmpegKit.execute('-version');
      final output = await session.getOutput();
      final match = RegExp(r'ffmpeg version (\S+)').firstMatch(output ?? '');
      return match?.group(1);
    } catch (e) {
      return null;
    }
  }
}