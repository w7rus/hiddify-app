import 'dart:io';
import 'dart:math';

import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Port and credentials for the core's local mixed (HTTP + SOCKS) inbound.
///
/// When [ConfigOptions.secureMixedInbound] is on these are minted fresh on every
/// core start and kept **in memory only** - never in shared preferences, which on
/// desktop is readable by any process running as the user.
class LocalProxySession {
  const LocalProxySession({required this.port, required this.username, required this.password, this.minted = true});

  /// Seed value before the first connect: [port] is only the configured fallback,
  /// not a port anything is listening on yet.
  const LocalProxySession.pending(this.port) : username = '', password = '', minted = false;

  final int port;
  final String username;
  final String password;

  /// False until [LocalProxySessionNotifier.regenerate] has run for this core start.
  final bool minted;

  bool get isAuthenticated => username.isNotEmpty && password.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalProxySession &&
          other.port == port &&
          other.username == username &&
          other.password == password &&
          other.minted == minted;

  @override
  int get hashCode => Object.hash(port, username, password, minted);

  /// Deliberately redacted - this ends up in logs.
  @override
  String toString() => "LocalProxySession(port: $port, authenticated: $isAuthenticated, minted: $minted)";
}

/// What this app's own HTTP client has to present to the local mixed inbound.
///
/// The bind list the core builds is exclusive, so there is only ever one mixed
/// inbound and one user list gating it. Three cases:
///
///  - hardening on: the per-session credentials minted here;
///  - hardening off but LAN sharing on with a password: the core still gates the
///    inbound, on the `hiddify` user, so the app has to present that too;
///  - neither: the inbound is open and nothing is sent.
final localProxyCredentialsProvider = Provider<LocalProxySession>((ref) {
  final session = ref.watch(localProxySessionProvider);
  if (session.isAuthenticated) return session;
  final lanPassword = ref.watch(ConfigOptions.allowConnectionFromLan)
      ? ref.watch(ConfigOptions.lanSharingPassword)
      : '';
  if (lanPassword.isEmpty) return session;
  return LocalProxySession(
    port: session.port,
    username: lanSharingUsername,
    password: lanPassword,
    minted: session.minted,
  );
});

/// The credentials to put in a LAN sharing link, which is a different choice
/// from the one [localProxyCredentialsProvider] makes for this app.
///
/// Both users sit on the same inbound, so either one authenticates. The
/// precedence differs because a shared link outlives the moment it is made: the
/// LAN password is stable, while the session credentials are re-minted on every
/// connect, so a link or QR built from those stops working at the next
/// reconnect. Prefer the stable one; fall back to the session so that sharing
/// still works with the secure local proxy on and no password set - otherwise
/// the link carries no credentials at all and the device it is handed to cannot
/// authenticate.
final lanSharingCredentialsProvider = Provider<LocalProxySession>((ref) {
  final session = ref.watch(localProxySessionProvider);
  final lanPassword = ref.watch(ConfigOptions.lanSharingPassword);
  if (lanPassword.isEmpty) return session;
  return LocalProxySession(
    port: session.port,
    username: lanSharingUsername,
    password: lanPassword,
    minted: session.minted,
  );
});

/// The username the core pairs with [ConfigOptions.lanSharingPassword], and the
/// one the sharing link hands out.
const lanSharingUsername = 'hiddify';

final localProxySessionProvider = NotifierProvider<LocalProxySessionNotifier, LocalProxySession>(
  LocalProxySessionNotifier.new,
);

class LocalProxySessionNotifier extends Notifier<LocalProxySession> with InfraLogger {
  /// IANA dynamic/private range - "random high port".
  static const _minPort = 49152;
  static const _maxPort = 65535;
  static const _bindAttempts = 16;

  /// Alphanumeric only: ':' and '@' would break the userinfo parsing that
  /// HttpClient.findProxy applies to "user:pass@host:port".
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  @override
  LocalProxySession build() => LocalProxySession.pending(ref.read(ConfigOptions.mixedPort));

  /// Called before the options are pushed to the core, so the fresh values are
  /// what the inbound is actually built with. Only at connect time - regenerating
  /// on every provider rebuild would restart the core in a loop.
  ///
  /// Credentials apply whenever hardening is on, including when the inbound is
  /// bound to the LAN: LAN clients authenticate with the separate LAN sharing
  /// password instead, which the core adds to the same inbound as a second user.
  Future<void> regenerate() async {
    if (!ref.read(ConfigOptions.secureMixedInbound)) {
      final configuredPort = ref.read(ConfigOptions.mixedPort);
      state = LocalProxySession(port: configuredPort, username: '', password: '');
      loggy.debug("hardening off, open inbound on configured port [$configuredPort]");
      return;
    }
    state = LocalProxySession(
      port: await _pickFreeHighPort(),
      username: _randomString(16),
      password: _randomString(24),
    );
    loggy.debug("minted local proxy session on random port [${state.port}]");
  }

  Future<int> _pickFreeHighPort() async {
    final random = Random.secure();
    for (var attempt = 0; attempt < _bindAttempts; attempt++) {
      final candidate = _minPort + random.nextInt(_maxPort - _minPort + 1);
      if (await _isBindable(candidate)) return candidate;
    }
    // Nothing stuck - let the kernel assign one. Still unpredictable, just not
    // guaranteed to land in the high range.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    loggy.debug("fell back to kernel-assigned port [$port]");
    return port;
  }

  /// Probes loopback rather than 0.0.0.0 on purpose: binding the wildcard address
  /// can raise a firewall prompt on Windows, and the core binds loopback in every
  /// case except opt-in LAN sharing.
  Future<bool> _isBindable(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  String _randomString(int length) {
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length))),
    );
  }
}
