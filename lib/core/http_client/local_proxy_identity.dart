import 'dart:io';
import 'dart:math';

import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';

/// Reads a provider. Matches `Ref.read`, `WidgetRef.read` and
/// `ProviderContainer.read` alike, so the minting below can be called from a
/// settings widget and from bootstrap without two copies of it.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

final _logger = Loggy('local proxy identity');

/// IANA dynamic/private range - "random high port".
const _minPort = 49152;
const _maxPort = 65535;
const _bindAttempts = 16;

/// Alphanumeric only: ':' and '@' would break the userinfo parsing that
/// HttpClient.findProxy applies to "user:pass@host:port".
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Gives the core's local mixed (HTTP + SOCKS) inbound a random high port and
/// random credentials, so a local process that scans loopback cannot find an
/// open proxy and tunnel its traffic through the user's exit node.
///
/// Minted when [ConfigOptions.secureMixedInbound] is switched on, and then kept.
/// It is deliberately *not* re-minted per connect: the port and credentials are
/// shown in settings and handed to LAN clients, so they have to be knowable
/// before the first connect and stable across a reconnect. Re-rolling is a
/// user action - switch the option off and on again.
///
/// Because it has to survive an app restart it lives in shared preferences, not
/// in memory. On desktop that means a process running as the same user can read
/// it. That is the same bar the core's gRPC token already sits at, and it still
/// defeats the threat this exists for: an unprivileged or opportunistic process
/// that finds the port by scanning has nothing to present. It is not a defence
/// against malware already running as the user, which could equally read the
/// token file and drive the core outright.
///
/// Persisting also fixes a case the per-connect version got wrong: a desktop
/// core outlives the app, so a freshly launched app attaches to a running core
/// and has to authenticate against the inbound that core already built.
/// Credentials are written before the port, and that order matters. Each write
/// is a separate preference and so a separate change to the options the core is
/// given; a change arriving while the service is running triggers a reconnect,
/// and config_option_notifier drops any further change inside its 100ms window
/// rather than queueing it. Writing the port first would therefore risk the core
/// being handed a random port with no credentials - an open proxy - and the
/// credential writes being discarded. This way every intermediate state the core
/// can observe is still authenticated: first the old port with new credentials,
/// then the new port with them.
Future<void> mintLocalProxyIdentity(ProviderReader read) async {
  final port = await _pickFreeHighPort();
  await read(ConfigOptions.mixedUsername.notifier).update(_randomString(16));
  await read(ConfigOptions.mixedPassword.notifier).update(_randomString(24));
  await read(ConfigOptions.mixedPort.notifier).update(port);
  _logger.debug("minted local proxy identity on random port [$port]");
}

/// Drops the credentials and puts the port back to its default, so the inbound
/// the core builds matches what the settings screen now claims: a plain, open
/// proxy on the well-known port. Port first here for the same reason as above -
/// the intermediate state is the default port still behind credentials.
Future<void> clearLocalProxyIdentity(ProviderReader read) async {
  await read(ConfigOptions.mixedPort.notifier).reset();
  await read(ConfigOptions.mixedUsername.notifier).update('');
  await read(ConfigOptions.mixedPassword.notifier).update('');
  _logger.debug("cleared local proxy identity");
}

/// Idempotent. Covers a fresh install, where [ConfigOptions.secureMixedInbound]
/// defaults on but nothing has been minted, and an upgrade from the build that
/// minted per connect and so persisted nothing.
Future<void> ensureLocalProxyIdentity(ProviderReader read) async {
  if (!read(ConfigOptions.secureMixedInbound)) return;
  if (read(ConfigOptions.mixedUsername).isNotEmpty && read(ConfigOptions.mixedPassword).isNotEmpty) {
    return;
  }
  await mintLocalProxyIdentity(read);
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
  _logger.debug("fell back to kernel-assigned port [$port]");
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
