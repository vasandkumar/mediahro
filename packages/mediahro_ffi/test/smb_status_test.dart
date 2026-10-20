import 'package:mediahro_ffi/mediahro_ffi.dart';
import 'package:test/test.dart';

void main() {
  test('NET-001 refused logons map to authenticationRequired by NT status, not message text', () {
    for (final s in const [
      0xC000006D, // LOGON_FAILURE
      0xC000006A, // WRONG_PASSWORD
      0xC0000064, // NO_SUCH_USER
      0xC000006E, // ACCOUNT_RESTRICTION
      0xC0000072, // ACCOUNT_DISABLED
      0xC0000234, // ACCOUNT_LOCKED_OUT
    ]) {
      expect(
        smbNtStatusError(s, connect: true),
        VirtualFileError.authenticationRequired,
        reason: s.toRadixString(16),
      );
      expect(smbNtStatusError(s), VirtualFileError.authenticationRequired);
    }
    // ACCESS_DENIED: credentials at session setup, permissions afterwards.
    expect(
      smbNtStatusError(0xC0000022, connect: true),
      VirtualFileError.authenticationRequired,
    );
    expect(smbNtStatusError(0xC0000022), VirtualFileError.permissionDenied);
    expect(
      smbNtStatusError(0xC00000CC, connect: true),
      VirtualFileError.notFound,
      reason: 'no such share',
    );
    expect(smbNtStatusError(0xC0000035), VirtualFileError.alreadyExists);
    expect(smbNtStatusError(0xC000007F), VirtualFileError.noSpace);
    expect(smbNtStatusError(0), isNull);
  });
}
