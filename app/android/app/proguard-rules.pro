# App R8 rules (lane C4a).

# sshj runs on the platform JCA without BouncyCastle (ADR-017). Its PuTTY v3
# key path references BouncyCastle's Argon2; Mediahro rejects those keys
# before reaching it (SshKeys.provider).
-dontwarn org.bouncycastle.**
