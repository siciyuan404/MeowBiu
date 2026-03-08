import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_audio/statistics.dart';

/// 进度回调函数类型
typedef void ProgressCallback(double progress);

/// 音频编辑服务
/// 使用 FFmpeg 实现音频裁切、提取等功能
class AudioEditorService {
  static Future<double?> getMediaDuration(String mediaPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(mediaPath);
      final information = session.getMediaInformation();
      
      if (information == null) {
        return null;
      }
      
      final durationStr = information.getDuration();
      if (durationStr == null) {
        return null;
      }
      
      return double.tryParse(durationStr);
    } catch (e) {
      print('Error getting media duration: $e');
      return null;
    }
  }

  /// 获取媒体信息（包含音频流信息）
  static Future<Map<String, dynamic>?> getMediaInfo(String mediaPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(mediaPath);
      final information = session.getMediaInformation();
      
      if (information == null) {
        return null;
      }
      
      final streams = information.getStreams();
      Map<String, dynamic>? audioStream;
      
      for (final stream in streams) {
        if (stream.getType() == 'audio') {
          audioStream = {
            'codec': stream.getCodec(),
            'sampleRate': stream.getSampleRate(),
            'channelLayout': stream.getChannelLayout(),
            'bitrate': stream.getBitrate(),
          };
          break;
        }
      }
      
      return {
        'duration': double.tryParse(information.getDuration() ?? '0'),
        'format': information.getFormat(),
        'audioStream': audioStream,
      };
    } catch (e) {
      print('Error getting media info: $e');
      return null;
    }
  }

  /// 裁切音频
  /// [audioPath] 源音频路径
  /// [startTime] 开始时间（秒）
  /// [duration] 裁切时长（秒）
  /// [onProgress] 进度回调（可选）
  /// 返回裁切后的新文件路径，失败返回 null
  static Future<String?> trimAudio({
    required String audioPath,
    required double startTime,
    required double duration,
    ProgressCallback? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/trimmed_$timestamp.mp3';
      
      // FFmpeg 裁切命令
      // -ss: 开始时间
      // -t: 时长
      // -c copy: 快速裁切（直接复制流，不重新编码）
      // 如果需要精确裁切，使用 -c:a libmp3lame -q:a 2
      
      String command;
      if (_isQuickTrimmable(audioPath)) {
        // 快速裁切：直接复制流
        command = '-ss $startTime -i "$audioPath" -t $duration -c copy "$outputPath"';
      } else {
        // 精确裁切：重新编码以保证精确的起止点
        command = '-ss $startTime -i "$audioPath" -t $duration -c:a libmp3lame -q:a 2 "$outputPath"';
      }
      
      print('FFmpeg trim command: $command');
      
      // 设置日志回调
      FFmpegKitConfig.enableStatisticsCallback((statistics) {
        if (onProgress != null && duration > 0) {
          final time = statistics.getTime();
          if (time > 0) {
            final progress = (time / 1000) / duration;
            onProgress(progress.clamp(0.0, 1.0));
          }
        }
      });
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        // 验证输出文件
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          if (fileSize > 0) {
            print('Audio trimmed successfully: $outputPath (${fileSize} bytes)');
            return outputPath;
          }
        }
      }
      
      // 输出失败日志
      final logs = await session.getAllLogsAsString();
      print('FFmpeg trim failed. Logs: $logs');
      
      return null;
    } catch (e) {
      print('Error trimming audio: $e');
      return null;
    }
  }

  /// 从视频中提取音频
  /// [videoPath] 源视频路径
  /// [startTime] 开始时间（秒）
  /// [duration] 提取时长（秒，null 表示提取整个视频的音频）
  /// [onProgress] 进度回调（可选）
  /// 返回提取后的音频文件路径，失败返回 null
  static Future<String?> extractAudioFromVideo({
    required String videoPath,
    double startTime = 0,
    double? duration,
    ProgressCallback? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/extracted_$timestamp.mp3';
      
      // 构建命令
      String command = '-ss $startTime -i "$videoPath"';
      
      if (duration != null) {
        command += ' -t $duration';
      }
      
      // 提取音频并转为 MP3
      // -vn: 不包含视频
      // -c:a libmp3lame: 使用 LAME 编码器
      // -q:a 2: 高质量 (VBR)
      command += ' -vn -c:a libmp3lame -q:a 2 "$outputPath"';
      
      print('FFmpeg extract command: $command');
      
      // 获取视频总时长用于计算进度
      double? totalDuration = duration;
      if (totalDuration == null) {
        final mediaInfo = await getMediaDuration(videoPath);
        if (mediaInfo != null) {
          totalDuration = mediaInfo - startTime;
        }
      }
      
      // 设置进度回调
      if (totalDuration != null && totalDuration > 0) {
        FFmpegKitConfig.enableStatisticsCallback((statistics) {
          if (onProgress != null) {
            final time = statistics.getTime();
            if (time > 0) {
              final progress = (time / 1000) / totalDuration!;
              onProgress(progress.clamp(0.0, 1.0));
            }
          }
        });
      }
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          if (fileSize > 0) {
            print('Audio extracted successfully: $outputPath (${fileSize} bytes)');
            return outputPath;
          }
        }
      }
      
      final logs = await session.getAllLogsAsString();
      print('FFmpeg extract failed. Logs: $logs');
      
      return null;
    } catch (e) {
      print('Error extracting audio: $e');
      return null;
    }
  }

  /// 转换音频格式
  /// [inputPath] 输入文件路径
  /// [outputFormat] 输出格式 (mp3, wav, aac, ogg)
  /// [onProgress] 进度回调（可选）
  static Future<String?> convertAudio({
    required String inputPath,
    required String outputFormat,
    ProgressCallback? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = 'converted_$timestamp';
      
      String outputPath;
      String codec;
      
      switch (outputFormat.toLowerCase()) {
        case 'mp3':
          outputPath = '${tempDir.path}/$baseName.mp3';
          codec = 'libmp3lame';
          break;
        case 'wav':
          outputPath = '${tempDir.path}/$baseName.wav';
          codec = 'pcm_s16le';
          break;
        case 'aac':
          outputPath = '${tempDir.path}/$baseName.aac';
          codec = 'aac';
          break;
        case 'ogg':
          outputPath = '${tempDir.path}/$baseName.ogg';
          codec = 'libvorbis';
          break;
        default:
          return null;
      }
      
      String command;
      if (outputFormat.toLowerCase() == 'wav') {
        command = '-i "$inputPath" -c:a $codec "$outputPath"';
      } else if (outputFormat.toLowerCase() == 'mp3') {
        command = '-i "$inputPath" -c:a $codec -q:a 2 "$outputPath"';
      } else {
        command = '-i "$inputPath" -c:a $codec "$outputPath"';
      }
      
      print('FFmpeg convert command: $command');
      
      // 获取总时长
      final totalDuration = await getMediaDuration(inputPath);
      
      if (totalDuration != null && totalDuration > 0) {
        FFmpegKitConfig.enableStatisticsCallback((statistics) {
          if (onProgress != null) {
            final time = statistics.getTime();
            if (time > 0) {
              final progress = (time / 1000) / totalDuration;
              onProgress(progress.clamp(0.0, 1.0));
            }
          }
        });
      }
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return outputPath;
        }
      }
      
      return null;
    } catch (e) {
      print('Error converting audio: $e');
      return null;
    }
  }

  /// 合并多个音频文件
  /// [inputPaths] 输入文件路径列表
  /// [onProgress] 进度回调（可选）
  static Future<String?> mergeAudios({
    required List<String> inputPaths,
    ProgressCallback? onProgress,
  }) async {
    if (inputPaths.isEmpty) return null;
    
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/merged_$timestamp.mp3';
      
      // 创建临时文件列表
      final listFile = File('${tempDir.path}/input_$timestamp.txt');
      final content = inputPaths.map((p) => "file '$p'").join('\n');
      await listFile.writeAsString(content);
      
      final command = '-f concat -safe 0 -i "${listFile.path}" -c:a libmp3lame -q:a 2 "$outputPath"';
      
      print('FFmpeg merge command: $command');
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      // 清理临时文件
      await listFile.delete();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return outputPath;
        }
      }
      
      return null;
    } catch (e) {
      print('Error merging audios: $e');
      return null;
    }
  }

  /// 调整音频音量
  /// [inputPath] 输入文件路径
  /// [volume] 音量倍数 (1.0 = 原音量, 0.5 = 半音量, 2.0 = 2倍音量)
  static Future<String?> adjustVolume({
    required String inputPath,
    required double volume,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/volume_$timestamp.mp3';
      
      final command = '-i "$inputPath" -filter:a "volume=$volume" -c:a libmp3lame -q:a 2 "$outputPath"';
      
      print('FFmpeg volume command: $command');
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return outputPath;
        }
      }
      
      return null;
    } catch (e) {
      print('Error adjusting volume: $e');
      return null;
    }
  }

  /// 淡入淡出效果
  /// [inputPath] 输入文件路径
  /// [fadeIn] 淡入时长（秒）
  /// [fadeOut] 淡出时长（秒）
  static Future<String?> fadeAudio({
    required String inputPath,
    double fadeIn = 0,
    double fadeOut = 0,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${tempDir.path}/fade_$timestamp.mp3';
      
      // 获取总时长
      final duration = await getMediaDuration(inputPath);
      if (duration == null) return null;
      
      String filterCommand = '';
      
      if (fadeIn > 0 && fadeOut > 0) {
        filterCommand = 'afade=t=in:st=0:d=$fadeIn,afade=t=out:st=${duration - fadeOut}:d=$fadeOut';
      } else if (fadeIn > 0) {
        filterCommand = 'afade=t=in:st=0:d=$fadeIn';
      } else if (fadeOut > 0) {
        filterCommand = 'afade=t=out:st=${duration - fadeOut}:d=$fadeOut';
      }
      
      if (filterCommand.isEmpty) return null;
      
      final command = '-i "$inputPath" -filter:a "$filterCommand" -c:a libmp3lame -q:a 2 "$outputPath"';
      
      print('FFmpeg fade command: $command');
      
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        final outputFile = File(outputPath);
        if (await outputFile.exists() && await outputFile.length() > 0) {
          return outputPath;
        }
      }
      
      return null;
    } catch (e) {
      print('Error fading audio: $e');
      return null;
    }
  }

  /// 判断是否可以使用快速裁切（直接复制流）
  static bool _isQuickTrimmable(String audioPath) {
    final ext = audioPath.toLowerCase().split('.').last;
    // 这些格式支持快速裁切
    return ['mp3', 'aac', 'm4a', 'ogg', 'flac', 'wav'].contains(ext);
  }

  /// 取消所有正在进行的 FFmpeg 任务
  static Future<void> cancelAll() async {
    await FFmpegKit.cancel();
  }

  /// 获取 FFmpeg 版本信息
  static Future<String?> getFFmpegVersion() async {
    try {
      final session = await FFmpegKit.execute('-version');
      final output = await session.getOutput();
      if (output != null && output.isNotEmpty) {
        final lines = output.split('\n');
        if (lines.isNotEmpty) {
          return lines.first;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
