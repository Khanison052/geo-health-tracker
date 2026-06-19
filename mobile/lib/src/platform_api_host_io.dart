import 'dart:io';

// Provided machine IP: 192.168.200.17
String getApiHost() {
  if (Platform.isAndroid) return '10.0.2.2'; // Android emulator -> host machine
  if (Platform.isIOS) return 'localhost'; // iOS simulator -> host machine
  // On desktop builds the backend is usually reachable via localhost.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return 'localhost';
  return '192.168.200.17';
}
