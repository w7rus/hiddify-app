import 'package:flutter/foundation.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'http_client_provider.g.dart';

@Riverpod(keepAlive: true)
DioHttpClient httpClient(Ref ref) {
  final client = DioHttpClient(
    timeout: const Duration(seconds: 15),
    userAgent: ref.watch(appInfoProvider).requireValue.userAgent,
    debug: kDebugMode,
  );

  void applyProxy() => client.setProxy(
    ref.read(ConfigOptions.mixedPort),
    ref.read(ConfigOptions.mixedUsername),
    ref.read(ConfigOptions.mixedPassword),
  );

  ref.listen(ConfigOptions.mixedPort, (_, _) => applyProxy(), fireImmediately: true);
  ref.listen(ConfigOptions.mixedUsername, (_, _) => applyProxy());
  ref.listen(ConfigOptions.mixedPassword, (_, _) => applyProxy());
  return client;
}
