import 'package:flutter/material.dart';
import 'package:hiddify/core/http_client/local_proxy_identity.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';

class InboundOptionsPage extends HookConsumerWidget {
  const InboundOptionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final secureMixedInbound = ref.watch(ConfigOptions.secureMixedInbound);

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.inbound.title)),
      body: ListView(
        children: [
          ChoicePreferenceWidget(
            selected: ref.watch(ConfigOptions.serviceMode),
            preferences: ref.watch(ConfigOptions.serviceMode.notifier),
            choices: ServiceMode.choices,
            title: t.pages.settings.inbound.serviceMode,
            icon: Icons.tune_rounded,
            presentChoice: (value) => value.present(t),
          ),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.inbound.strictRoute),
            secondary: const Icon(Icons.merge_rounded),
            value: ref.watch(ConfigOptions.strictRoute),
            onChanged: ref.read(ConfigOptions.strictRoute.notifier).update,
          ),
          ChoicePreferenceWidget(
            selected: ref.watch(ConfigOptions.tunImplementation),
            preferences: ref.watch(ConfigOptions.tunImplementation.notifier),
            choices: TunImplementation.values,
            title: t.pages.settings.inbound.tunImplementation,
            icon: Icons.trip_origin_rounded,
            presentChoice: (value) => value.name,
          ),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.inbound.secureMixedInbound),
            subtitle: Text(
              secureMixedInbound && ref.watch(ConfigOptions.serviceMode) == ServiceMode.systemProxy
                  ? t.pages.settings.inbound.secureMixedInboundSystemProxyWarning
                  : t.pages.settings.inbound.secureMixedInboundDescription,
              style: secureMixedInbound && ref.watch(ConfigOptions.serviceMode) == ServiceMode.systemProxy
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            secondary: const Icon(Icons.lock_rounded),
            value: secureMixedInbound,
            // Switching on is what rolls the port and credentials; switching off
            // puts the port back and drops them. That makes this the one place
            // they change, so the value shown below is always the live one and
            // re-rolling is something the user asks for rather than something
            // that happens under a link they already handed out.
            onChanged: (bool value) async {
              await ref.read(ConfigOptions.secureMixedInbound.notifier).update(value);
              if (value) {
                await mintLocalProxyIdentity(ref.read);
              } else {
                await clearLocalProxyIdentity(ref.read);
              }
            },
          ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.mixedPort),
            preferences: ref.watch(ConfigOptions.mixedPort.notifier),
            title: t.pages.settings.inbound.mixedPort,
            icon: Icons.device_hub_rounded,
            inputToValue: int.tryParse,
            digitsOnly: true,
            validateInput: isPort,
          ),
          if (PlatformUtils.isLinux)
            ValuePreferenceWidget(
              value: ref.watch(ConfigOptions.tproxyPort),
              preferences: ref.watch(ConfigOptions.tproxyPort.notifier),
              title: t.pages.settings.inbound.tproxyPort,
              icon: Icons.device_hub_rounded,
              inputToValue: int.tryParse,
              digitsOnly: true,
              validateInput: isPort,
            ),
          if (PlatformUtils.isLinux || PlatformUtils.isMacOS)
            ValuePreferenceWidget(
              value: ref.watch(ConfigOptions.redirectPort),
              preferences: ref.watch(ConfigOptions.redirectPort.notifier),
              title: t.pages.settings.inbound.redirectPort,
              icon: Icons.device_hub_rounded,
              inputToValue: int.tryParse,
              digitsOnly: true,
              validateInput: isPort,
            ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.directPort),
            preferences: ref.watch(ConfigOptions.directPort.notifier),
            title: t.pages.settings.inbound.directPort,
            icon: Icons.device_hub_rounded,
            inputToValue: int.tryParse,
            digitsOnly: true,
            validateInput: isPort,
          ),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.inbound.allowConnectionFromLan),
            secondary: const Icon(Icons.share_rounded),
            value: ref.watch(ConfigOptions.allowConnectionFromLan),
            onChanged: (bool value) async {
              await ref.read(ConfigOptions.allowConnectionFromLan.notifier).update(value);
              if (value == true) {
                final ip = await NetworkInfo().getWifiIP();
                // final ipp = Networkinfo
                if (ip == null) return;
                // Carry the credentials. The core gates this one inbound on them,
                // and the bind list is exclusive, so LAN sharing publishes the
                // *same* authenticated listener - a bare socks://ip:port link is
                // one no device on the network could authenticate with.
                final username = ref.read(ConfigOptions.mixedUsername);
                final password = ref.read(ConfigOptions.mixedPassword);
                final userinfo = username.isEmpty || password.isEmpty ? '' : '$username:$password@';
                final target = 'socks://$userinfo$ip:${ref.read(ConfigOptions.mixedPort)}';
                final link = '#profile-title: LAN only\n$target#LAN only';
                await ref.read(dialogNotifierProvider.notifier).showQrCode(link, message: target);
              }
            },
          ),
        ],
      ),
    );
  }
}
