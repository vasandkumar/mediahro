import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro/features/photos/vault/pin_pad.dart';
import 'package:mediahro/features/photos/vault/vault_manager.dart';
import 'package:mediahro/features/photos/vault/vault_providers.dart';
import 'package:mediahro/platform/vault_crypto.dart';

/// "Try again in 2 minutes": the wait rounded up to a unit people read.
String vaultWaitText(AppLocalizations l10n, Duration d) {
  if (d < const Duration(seconds: 90)) {
    return l10n.photosVaultTimeSeconds(d.inSeconds.clamp(1, 90));
  }
  if (d < const Duration(minutes: 90)) {
    return l10n.photosVaultTimeMinutes((d.inSeconds / 60).ceil());
  }
  if (d < const Duration(hours: 36)) {
    return l10n.photosVaultTimeHours((d.inMinutes / 60).ceil());
  }
  return l10n.photosVaultTimeDays((d.inHours / 24).ceil());
}

/// What to tell the user of a refused attempt; empty when it opened.
String vaultOutcomeText(AppLocalizations l10n, VaultOpenResult r) =>
    switch (r.outcome) {
      VaultOutcome.opened || VaultOutcome.needsSetup => '',
      VaultOutcome.wrongPin => l10n.photosVaultWrongPin,
      VaultOutcome.waitToRetry => l10n.photosVaultWait(
        vaultWaitText(l10n, r.wait ?? const Duration(seconds: 30)),
      ),
      VaultOutcome.cancelled => l10n.photosVaultCancelled,
      VaultOutcome.notEnrolled => l10n.photosVaultNotEnrolled,
      VaultOutcome.fingerprintInvalidated =>
        l10n.photosVaultFingerprintInvalidated,
      VaultOutcome.keyLost => l10n.photosVaultKeyLost,
      VaultOutcome.lockedOut => l10n.photosVaultLockedOut,
      VaultOutcome.authFailed => l10n.photosVaultAuthFailed,
      VaultOutcome.unavailable => l10n.photosVaultUnavailable,
      VaultOutcome.damaged => l10n.photosVaultDamaged,
      VaultOutcome.noFingerprint => l10n.photosVaultCancelled,
      VaultOutcome.pinNotAllowed => l10n.photosVaultPinNotAllowed,
      VaultOutcome.pinTooShort => l10n.photosVaultPinShort,
    };

/// The one way into the vault (IMG-011, ADR-040): a PIN pad, and the
/// fingerprint button if it was turned on. Before there is a vault, the
/// set-up form. It looks and behaves the same whichever vault a PIN opens.
class VaultGate extends ConsumerStatefulWidget {
  const VaultGate({this.onOpened, super.key});

  /// Called once the vault is open.
  final VoidCallback? onOpened;

  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate> {
  final GlobalKey<PinPadState> _pad = GlobalKey();
  String _message = '';
  bool _busy = false;
  bool _lost = false;

  void _finish(VaultOpenResult r) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _message = vaultOutcomeText(l10n, r);
      // The way out (Reset) is offered only when the phone key itself is gone,
      // which the manager checks before it says so.
      _lost = r.outcome == VaultOutcome.keyLost;
    });
    // A refused fingerprint may have switched itself off.
    if (!r.isOpen) ref.invalidate(vaultFingerprintOnProvider);
    if (r.isOpen) widget.onOpened?.call();
  }

  Future<void> _pin(String pin) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    final r = await ref.read(vaultSessionProvider.notifier).unlockWithPin(pin);
    _finish(r);
  }

  Future<void> _fingerprint() async {
    setState(() {
      _busy = true;
      _message = '';
    });
    final r = await ref
        .read(vaultSessionProvider.notifier)
        .unlockWithFingerprint();
    _finish(r);
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photosVaultResetTitle),
        content: Text(l10n.photosVaultResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photosCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photosVaultResetConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final manager = await ref.read(vaultManagerProvider.future);
    try {
      await manager.reset();
    } on VaultCryptoException catch (e) {
      // Nothing was deleted; the user can try again.
      if (mounted) {
        setState(
          () => _message = vaultOutcomeText(
            AppLocalizations.of(context),
            VaultOpenResult(VaultManager.outcomeOf(e)),
          ),
        );
      }
      return;
    }
    ref
      ..invalidate(vaultExistsProvider)
      ..invalidate(vaultFingerprintOnProvider);
    if (mounted) {
      setState(() {
        _lost = false;
        _message = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = ref.watch(vaultManagerProvider);
    final exists = ref.watch(vaultExistsProvider);
    return manager.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _Notice(text: l10n.photosVaultUnavailable),
      data: (_) => exists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Notice(text: l10n.photosVaultUnavailable),
        data: (has) => has
            ? _locked(context, l10n)
            : VaultSetUpForm(onOpened: widget.onOpened),
      ),
    );
  }

  Widget _locked(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final bio = ref.watch(vaultFingerprintOnProvider).value ?? false;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                l10n.photosVaultEnterPin,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              PinPad(
                key: _pad,
                enabled: !_busy,
                onSubmit: (p) => unawaited(_pin(p)),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              if (bio && !_lost)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.fingerprint),
                    onPressed: _busy ? null : () => unawaited(_fingerprint()),
                    label: Text(l10n.photosVaultFingerprintAction),
                  ),
                ),
              if (_lost)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(
                    onPressed: () => unawaited(_reset()),
                    child: Text(l10n.photosVaultReset),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

/// The first-time form: a PIN, an optional second vault, the fingerprint.
class VaultSetUpForm extends ConsumerStatefulWidget {
  const VaultSetUpForm({this.onOpened, super.key});

  final VoidCallback? onOpened;

  @override
  ConsumerState<VaultSetUpForm> createState() => _VaultSetUpFormState();
}

class _VaultSetUpFormState extends ConsumerState<VaultSetUpForm> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  final TextEditingController _second = TextEditingController();
  bool _fingerprint = false;
  bool _busy = false;
  String? _error;
  String _message = '';

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    _second.dispose();
    super.dispose();
  }

  static final RegExp _valid = RegExp(r'^\d{6,12}$');

  Future<void> _go() async {
    final l10n = AppLocalizations.of(context);
    String? error;
    if (!_valid.hasMatch(_pin.text) ||
        (_second.text.isNotEmpty && !_valid.hasMatch(_second.text))) {
      error = l10n.photosVaultPinShort;
    } else if (_pin.text != _repeat.text) {
      error = l10n.photosVaultPinMismatch;
    } else if (_second.text == _pin.text) {
      error = l10n.photosVaultSecondSame;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
      _message = '';
    });
    final r = await ref
        .read(vaultSessionProvider.notifier)
        .setUp(
          pin: _pin.text,
          secondPin: _second.text.isEmpty ? null : _second.text,
          fingerprint: _fingerprint,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = vaultOutcomeText(l10n, r);
    });
    if (r.isOpen) {
      ref
        ..invalidate(vaultExistsProvider)
        ..invalidate(vaultFingerprintOnProvider);
      widget.onOpened?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    InputDecoration deco(String label, {String? error}) => InputDecoration(
      labelText: label,
      errorText: error,
      border: const OutlineInputBorder(),
    );
    Widget pinField(TextEditingController c, String label, {String? error}) =>
        TextField(
          controller: c,
          enabled: !_busy,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: deco(label, error: error).copyWith(counterText: ''),
        );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                l10n.photosVaultSetUpTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(l10n.photosVaultIntro, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              pinField(_pin, l10n.photosVaultPinLabel),
              const SizedBox(height: 4),
              Text(l10n.photosVaultPinHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              pinField(_repeat, l10n.photosVaultPinRepeat),
              const SizedBox(height: 20),
              Text(
                l10n.photosVaultSecondTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.photosVaultSecondBody,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              pinField(_second, l10n.photosVaultSecondPin),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.photosVaultUseFingerprint),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.photosVaultFingerprintNote),
                    const SizedBox(height: 4),
                    Text(l10n.photosVaultFingerprintWarning),
                  ],
                ),
                value: _fingerprint,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _fingerprint = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _message,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_go()),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.photosVaultSetUp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
