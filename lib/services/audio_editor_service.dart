import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// 进度回调函数类型
typedef void ProgressCallback(double progress);

/// 错误信息回调函数类型
typedef void ErrorCallback(String errorMessage);

/// 音频编辑服务
/// 使用 ffmpeg_kit_flutter_audio_min 实现音频处理功能
class AudioEditorService {
  static final AudioPlayer _durationPlayer = AudioPlayer();

  // 当前活动的 FFmpeg 会话，用于支持取消正在进行的任务
  static FFmpegSession? _activeSession;

  /// 获取媒体时长（返回毫秒）
  /// 音频文件通过 just_audio 直接读取；视频文件通过 FFprobe 快速探测，
  /// 不再对整个视频解码，可秒级返回时长。
  static Future<double?> getMediaDuration(String mediaPath) async {
    try {
      // 音频文件：just_audio 直接读取，速度快
      if (mediaPath.endsWith('.mp3') ||
          mediaPath.endsWith('.wav') ||
          mediaPath.endsWith('.m4a') ||
          mediaPath.endsWith('.aac') ||
          mediaPath.endsWith('.ogg') ||
          mediaPath.endsWith('.flac')) {
        final duration = await _durationPlayer.setFilePath(mediaPath);
        return duration?.inMilliseconds.toDouble();
      }

      // 视频及其他格式：使用 FFprobe 读取容器信息，不解码视频流
      final session = await FFprobeKit.getMediaInformation(mediaPath);
      final info = session.getMediaInformation();
      final durationStr = info?.getDuration();
      if (durationStr != null) {
        final seconds = double.tryParse(durationStr);
        if (seconds != null && seconds > 0) {
          return seconds * 1000;
        }
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
  /// [startTime] 开始时间(秒)，[duration] 持续时长(秒)
  /// [precise] 精确模式：在输入之后精确定位起点，精度高但速度较慢；
  ///   快速模式（默认）：在输入之前定位起点，速度快。
  /// 处理过程中通过 [onProgress] 实时回报进度，失败时通过 [onError] 返回具体错误。
  static Future<String?> trimAudio({
    required String audioPath,
    required double startTime,
    required double duration,
    bool precise = false,
    ProgressCallback? onProgress,
    ErrorCallback? onError,
  }) async {
    try {
      final inputFile = File(audioPath);
      if (!await inputFile.exists()) {
        onError?.call('音频文件不存在: $audioPath');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/trimmed_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final startStr = startTime.toStringAsFixed(3);
      final durStr = duration.toStringAsFixed(3);

      final List<String> args;
      if (precise) {
        // 精确模式：-ss 放在输入之后，解码到目标位置再输出（慢但准）
        args = [
          '-i', audioPath,
          '-ss', startStr,
          '-t', durStr,
          '-c:a', 'libmp3lame',
          '-q:a', '2',
          '-y', outputPath,
        ];
      } else {
        // 快速模式：-ss 放在输入之前，直接从目标位置开始处理（快）
        args = [
          '-ss', startStr,
          '-i', audioPath,
          '-t', durStr,
          '-c:a', 'libmp3lame',
          '-q:a', '2',
          '-y', outputPath,
        ];
      }

      return await _executeWithProgress(
        args: args,
        outputPath: outputPath,
        totalMs: duration * 1000,
        onProgress: onProgress,
        onError: onError,
      );
    } catch (e) {
      print('裁切音频失败: $e');
      onError?.call('裁切音频失败: $e');
      return null;
    }
  }

  /// 从视频中提取音频
  /// [startTime] 开始时间(秒)，[duration] 持续时长(秒，为空则提取到结尾)
  /// [precise] 精确模式：前置快速定位 + 输入后精确定位，起点更准但较慢；
  ///   快速模式（默认）：前置快速定位，直接从关键帧附近开始提取，速度快。
  /// 处理过程中通过 [onProgress] 实时回报进度，失败时通过 [onError] 返回具体错误。
  static Future<String?> extractAudioFromVideo({
    required String videoPath,
    double startTime = 0,
    double? duration,
    bool precise = false,
    ProgressCallback? onProgress,
    ErrorCallback? onError,
  }) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        onError?.call('视频文件不存在: $videoPath');
        return null;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/extracted_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final startStr = startTime.toStringAsFixed(3);
      final List<String> args = <String>[];

      // 前置 -ss：快速定位到起始位置附近（关键帧），避免从视频头开始完整解码
      if (startTime > 0) {
        args.addAll(['-ss', startStr]);
      }
      args.addAll(['-i', videoPath]);
      // 精确模式：输入后再做一次精确定位，修正关键帧间隔带来的起点误差
      if (precise && startTime > 0) {
        args.addAll(['-ss', startStr]);
      }
      if (duration != null && duration > 0) {
        args.addAll(['-t', duration.toStringAsFixed(3)]);
      }
      args.addAll([
        '-vn', // 丢弃视频流
        '-map', '0:a:0', // 只取第一个音轨
        '-c:a', 'libmp3lame',
        '-q:a', '2',
        '-y', outputPath,
      ]);

      return await _executeWithProgress(
        args: args,
        outputPath: outputPath,
        totalMs: (duration ?? 0) * 1000,
        onProgress: onProgress,
        onError: onError,
      );
    } catch (e) {
      print('提取音频失败: $e');
      onError?.call('提取音频失败: $e');
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

  /// 取消当前正在进行的 FFmpeg 任务（裁切/提取/转换等）
  static Future<void> cancelCurrent() async {
    final session = _activeSession;
    _activeSession = null;
    if (session != null) {
      await session.cancel();
    }
  }

  /// 取消所有正在进行的任务
  static Future<void> cancelAll() async {
    await FFmpegKit.cancel();
  }

  /// 执行异步 FFmpeg 任务并实时回报进度
  /// [args] FFmpeg 参数列表；[outputPath] 成功后返回的输出路径；
  /// [totalMs] 处理总时长（毫秒），用于计算进度。
  /// 返回输出路径（成功）或 null（失败/取消）。
  static Future<String?> _executeWithProgress({
    required List<String> args,
    required String outputPath,
    required double totalMs,
    ProgressCallback? onProgress,
    ErrorCallback? onError,
  }) async {
    final completer = Completer<String?>();
    _activeSession = null;

    try {
      final session = await FFmpegKit.executeWithArgumentsAsync(
        args,
        (session) async {
          // 任务结束，清除活动会话引用
          _activeSession = null;
          try {
            final returnCode = await session.getReturnCode();
            if (ReturnCode.isSuccess(returnCode)) {
              onProgress?.call(1.0);
              completer.complete(outputPath);
            } else if (ReturnCode.isCancel(returnCode)) {
              // 用户主动取消，不视为错误
              completer.complete(null);
            } else {
              final logs = await session.getAllLogsAsString();
              final errorMsg = _extractErrorMessage(logs);
              print('FFmpeg 处理失败: $errorMsg');
              onError?.call(errorMsg);
              completer.complete(null);
            }
          } catch (e) {
            print('读取 FFmpeg 结果失败: $e');
            onError?.call('处理失败: $e');
            completer.complete(null);
          }
        },
        null,
        (statistics) {
          if (totalMs <= 0) return;
          final timeMs = statistics.getTime().toDouble();
          if (timeMs <= 0) return;
          var progress = (timeMs / totalMs).clamp(0.0, 1.0);
          // 避免提前卡在 100%，完成后统一由完成回调置为 1.0
          if (progress >= 1.0) progress = 0.99;
          onProgress?.call(progress);
        },
      );
      _activeSession = session;
    } catch (e) {
      print('启动 FFmpeg 任务失败: $e');
      onError?.call('启动 FFmpeg 任务失败: $e');
      completer.complete(null);
    }

    return completer.future;
  }

  /// 从 FFmpeg 日志中提取简洁的错误信息
  static String _extractErrorMessage(String? logs) {
    if (logs == null || logs.trim().isEmpty) {
      return 'FFmpeg 处理失败';
    }
    final lines = logs.split('\n');
    // 优先提取包含 Error 的行，取最后一条
    final errorLines = lines
        .where((l) => l.toLowerCase().contains('error') && l.trim().isNotEmpty)
        .toList();
    if (errorLines.isNotEmpty) {
      return errorLines.last.trim();
    }
    // 兜底：返回最后几条非空日志
    final tail = lines.where((l) => l.trim().isNotEmpty).toList();
    if (tail.isEmpty) return 'FFmpeg 处理失败';
    return tail.length <= 3
        ? tail.join('\n')
        : tail.sublist(tail.length - 3).join('\n');
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