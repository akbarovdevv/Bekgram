// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

const bool supportsRecordedVoiceFileAccess = true;

Future<String> createVoiceRecordingPath() async {
  return 'bekgram-web-voice-${DateTime.now().microsecondsSinceEpoch}';
}

Future<Uint8List?> readVoiceRecordingBytes(String path) async {
  if (path.isEmpty) return null;
  final request = await html.HttpRequest.request(
    path,
    method: 'GET',
    responseType: 'arraybuffer',
  );

  final response = request.response;
  if (response is ByteBuffer) {
    return Uint8List.view(response);
  }
  if (response is Uint8List) {
    return response;
  }
  return null;
}

Future<void> deleteVoiceRecordingFile(String? path) async {
  if (path == null || path.isEmpty) return;
  if (path.startsWith('blob:')) {
    html.Url.revokeObjectUrl(path);
  }
}
