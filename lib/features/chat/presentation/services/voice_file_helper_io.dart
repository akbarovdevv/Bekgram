import 'dart:io';
import 'dart:typed_data';

const bool supportsRecordedVoiceFileAccess = true;

Future<String> createVoiceRecordingPath() async {
  return '${Directory.systemTemp.path}/bekgram-voice-${DateTime.now().microsecondsSinceEpoch}';
}

Future<Uint8List?> readVoiceRecordingBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<void> deleteVoiceRecordingFile(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // ignore temporary file cleanup errors
  }
}
