// Conditional export: choose IO implementation when running on native (dart:io),
// otherwise use the web/local stub. Paths are relative to this file.
export 'platform_api_host_stub.dart'
    if (dart.library.io) 'platform_api_host_io.dart';
