# Refreshes the `evojam-mfa` AWS profile with temporary, MFA-backed session
# credentials. Reads the TOTP from the YubiKey (touch required), calls
# `sts get-session-token` against the base `evojam` profile, and writes the
# returned access key / secret / session token back into `evojam-mfa`.
{pkgs, ...}: let
  ykman = "${pkgs.yubikey-manager}/bin/ykman";
  aws = "${pkgs.awscli2}/bin/aws";
  jq = "${pkgs.jq}/bin/jq";

  # YubiKey OATH account label (what `ykman oath accounts list` shows).
  oathAccount = "arn:aws:iam::139060264378:mfa/mwadon";
  # The MFA device serial AWS expects on `get-session-token`.
  mfaSerial = "arn:aws:iam::139060264378:mfa/yubi-totp";
  baseProfile = "evojam";
  targetProfile = "evojam-mfa";
  duration = "43200"; # 12h, the account's max
in
  pkgs.writeShellScriptBin "aws-evojam-mfa" ''
    set -euo pipefail

    echo "Touch your YubiKey to read the MFA code..." >&2
    code="$(${ykman} oath accounts code -s '${oathAccount}' | tr -d '[:space:]')"
    if [ -z "$code" ]; then
      echo "error: could not read a TOTP code from the YubiKey" >&2
      exit 1
    fi

    echo "Requesting a session token from AWS..." >&2
    creds="$(${aws} sts get-session-token \
      --profile '${baseProfile}' \
      --serial-number '${mfaSerial}' \
      --token-code "$code" \
      --duration-seconds '${duration}')"

    akid="$(printf '%s' "$creds" | ${jq} -r .Credentials.AccessKeyId)"
    secret="$(printf '%s' "$creds" | ${jq} -r .Credentials.SecretAccessKey)"
    token="$(printf '%s' "$creds" | ${jq} -r .Credentials.SessionToken)"
    expires="$(printf '%s' "$creds" | ${jq} -r .Credentials.Expiration)"

    ${aws} configure set aws_access_key_id     "$akid"   --profile '${targetProfile}'
    ${aws} configure set aws_secret_access_key "$secret" --profile '${targetProfile}'
    ${aws} configure set aws_session_token     "$token"  --profile '${targetProfile}'

    echo "✓ profile '${targetProfile}' refreshed — valid until $expires" >&2
  ''
