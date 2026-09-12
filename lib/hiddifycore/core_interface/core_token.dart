import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';

/// Bearer token for the core's gRPC API.
///
/// The Core service can enumerate configured servers, stream logs, switch
/// outbounds and rewrite settings, and on every platform it is reached over a
/// plain loopback socket. The core writes this token into its working directory
/// with owner-only permissions at setup; presenting it is what distinguishes this
/// app from any other local process that finds the port.
///
/// Reading it from disk (rather than passing one in) also covers the desktop case
/// where the core outlives the app: a freshly launched app attaches to a running
/// core and picks up the token it already minted.
const coreTokenHeader = 'x-hiddify-core-token';
const _coreTokenFileName = 'grpc.token';

/// Reads the token the core persisted. Empty when the core predates token
/// support or has not completed setup, in which case calls proceed unauthenticated
/// exactly as before.
Future<String> readCoreToken(Directories directories) async {
  try {
    final file = File('${directories.workingDir.path}${Platform.pathSeparator}$_coreTokenFileName');
    if (!await file.exists()) return '';
    return (await file.readAsString()).trim();
  } catch (_) {
    return '';
  }
}

/// Default call options carrying the token, or none when there is no token.
CallOptions coreCallOptions(String token) =>
    token.isEmpty ? CallOptions() : CallOptions(metadata: {coreTokenHeader: token});
