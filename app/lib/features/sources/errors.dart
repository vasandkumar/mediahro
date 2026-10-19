import 'package:mediahro/app/l10n/gen/app_localizations.dart';
import 'package:mediahro_ffi/mediahro_ffi.dart';

/// User-facing copy for file errors (docs/06 §8): plain sentence, no jargon;
/// technical detail goes to the info sheet.
String fileErrorMessage(AppLocalizations l10n, VirtualFileError e) =>
    switch (e) {
      VirtualFileError.notFound => l10n.sourcesErrorNotFound,
      VirtualFileError.permissionDenied => l10n.sourcesErrorPermission,
      VirtualFileError.authenticationRequired => l10n.sourcesErrorAuth,
      VirtualFileError.unreachable => l10n.sourcesErrorUnreachable,
      VirtualFileError.timeout => l10n.sourcesErrorTimeout,
      VirtualFileError.closed || VirtualFileError.io => l10n.sourcesErrorIo,
      VirtualFileError.unsupported => l10n.sourcesErrorUnsupported,
      VirtualFileError.alreadyExists => l10n.sourcesErrorExists,
      VirtualFileError.noSpace => l10n.sourcesErrorNoSpace,
      VirtualFileError.untrustedCertificate => l10n.sourcesErrorCertificate,
    };
