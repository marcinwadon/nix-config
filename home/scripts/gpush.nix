# gpush — push the current branch to origin's repo under the correct GitHub
# account, via an explicit HTTPS URL so SSH-origin (Yubikey-gated) repos don't
# prompt for a touch, and so HTTPS-origin repos don't resolve to the wrong gh
# account. The account's token is resolved at push time inside a credential
# helper (never placed in argv). A bare --force-with-lease is auto-pinned to
# the current remote SHA (pushing via an ad-hoc URL otherwise triggers a
# "stale info" rejection because origin's lease ref is stale).
{pkgs, ...}: let
  gh = "${pkgs.gh}/bin/gh";
  git = "${pkgs.git}/bin/git";
in
  pkgs.writeShellScriptBin "gpush" ''
    set -euo pipefail

    dry_run=0
    args=()
    for a in "$@"; do
      case "$a" in
        --dry-run) dry_run=1 ;;
        *) args+=("$a") ;;
      esac
    done

    origin="$(${git} remote get-url origin)"
    ownerrepo="$(printf '%s' "$origin" \
      | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"
    case "$ownerrepo" in
      */*) : ;;
      *) echo "error: origin '$origin' is not a github.com remote" >&2; exit 1 ;;
    esac
    owner="''${ownerrepo%%/*}"
    repo="''${ownerrepo#*/}"

    case "$owner" in
      marcinwadon) acct="marcinwadon" ;;
      parloa)      acct="marcin-wadon-parloa" ;;
      evojam)      acct="marcinwadon" ;;
      *)
        acct="$(${gh} api user --jq .login)"
        echo "warning: unknown owner '$owner'; using active gh account '$acct'" >&2
        ;;
    esac

    # Resolve how to fetch this account's token: keyring accounts answer to
    # --user; an env-var/active account (e.g. marcinwadon via GITHUB_TOKEN)
    # only answers to bare `gh auth token`.
    if ${gh} auth token --user "$acct" >/dev/null 2>&1; then
      token_cmd="${gh} auth token --user $acct"
    elif [ "$acct" = "$(${gh} api user --jq .login 2>/dev/null || true)" ]; then
      token_cmd="${gh} auth token"
    else
      echo "error: gh account '$acct' not available; run: gh auth login" >&2
      exit 1
    fi

    helper="!f(){ echo username=$acct; echo \"password=\$($token_cmd)\"; }; f"

    branch="$(${git} branch --show-current)"
    [ -n "$branch" ] || { echo "error: detached HEAD; check out a branch" >&2; exit 1; }
    refspec="HEAD:$branch"
    url="https://github.com/$owner/$repo.git"

    pinned_args=()
    for a in "''${args[@]:-}"; do
      if [ "$a" = "--force-with-lease" ]; then
        remote_sha="$(${git} -c credential.helper= -c credential.helper="$helper" \
          ls-remote "$url" "$branch" | awk '{print $1}')"
        if [ -n "$remote_sha" ]; then
          pinned_args+=("--force-with-lease=$branch:$remote_sha")
        else
          pinned_args+=("--force-with-lease")
        fi
      else
        pinned_args+=("$a")
      fi
    done

    echo "gpush: $owner/$repo  branch=$branch  account=$acct" >&2
    echo "  url=$url  refspec=$refspec  extra=''${pinned_args[*]:-}" >&2
    if [ "$dry_run" -eq 1 ]; then
      echo "  (dry-run: not pushing)" >&2
      exit 0
    fi

    ${git} -c credential.helper= -c credential.helper="$helper" \
      push "$url" "$refspec" "''${pinned_args[@]:-}"
  ''
