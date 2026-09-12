import 'package:flutter/material.dart';
import 'package:hiddify/core/http_client/local_proxy_session.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/lan_sharing_tile.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class InboundOptionsPage extends HookConsumerWidget with AppLogger {
  const InboundOptionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final secureMixedInbound = ref.watch(ConfigOptions.secureMixedInbound);
    final session = ref.watch(localProxySessionProvider);

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
            onChanged: ref.read(ConfigOptions.secureMixedInbound.notifier).update,
          ),
          if (secureMixedInbound)
            ListTile(
              leading: const Icon(Icons.device_hub_rounded),
              title: Text(t.pages.settings.inbound.mixedPort),
              // Before the first connect there is no live port yet - the seed value
              // is just the configured fallback, so don't present it as the real one.
              subtitle: Text(
                session.minted
                    ? t.pages.settings.inbound.mixedPortRandomized(port: session.port)
                    : t.pages.settings.inbound.mixedPortAssignedOnConnect,
              ),
            )
          else
            ValuePreferenceWidget(
              value: ref.watch(ConfigOptions.mixedPort),
              preferences: ref.watch(ConfigOptions.mixedPort.notifier),
              title: t.pages.settings.inbound.mixedPort,
              icon: Icons.device_hub_rounded,
              inputToValue: int.tryParse,
              digitsOnly: true,
              validateInput: isPort,
              trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableMixedPort),
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
              trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableTproxyPort),
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
              trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableRedirectPort),
            ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.directPort),
            preferences: ref.watch(ConfigOptions.directPort.notifier),
            title: t.pages.settings.inbound.directPort,
            icon: Icons.device_hub_rounded,
            inputToValue: int.tryParse,
            digitsOnly: true,
            validateInput: isPort,
            trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableDirectPort),
          ),
          SwitchListTile.adaptive(
            title: Text(t.pages.settings.inbound.enableClashApi),
            subtitle: Text(
              ref.watch(ConfigOptions.enableClashApi)
                  ? t.pages.settings.inbound.enableClashApiWarning
                  : t.pages.settings.inbound.enableClashApiDescription,
              style: ref.watch(ConfigOptions.enableClashApi)
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            secondary: const Icon(Icons.api_rounded),
            value: ref.watch(ConfigOptions.enableClashApi),
            onChanged: ref.read(ConfigOptions.enableClashApi.notifier).update,
          ),
          const LanSharingPreferenceWidget(),
        ],
      ),
    );
  }
}
