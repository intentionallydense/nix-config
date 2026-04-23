# User-facing API keys, encrypted with sops-nix, exposed to fish as env vars.
#
# How it works:
#   1. Keys live encrypted in ../../../secrets/secrets.yaml (edit via `sops`).
#   2. At activation, sops-nix decrypts declared secrets to /run/secrets/<name>.
#   3. sops.templates interpolates placeholders into a fish-sourceable file
#      at /run/secrets-rendered/user-api-keys.fish.
#   4. fish shellInit sources that file on every new shell, so $MOONSHOT_API_KEY
#      et al. are available to any process launched from fish.
#
# Adding a new key:
#   - `sops ../../../secrets/secrets.yaml` → add `<name>: <value>` at top level.
#   - Add `<name>.owner = "fluoride";` to sops.secrets below.
#   - Add a `set -gx <VAR> "${config.sops.placeholder.<name>}"` line to the template.
#   - Rebuild.
#
# Used by: hosts/carbon/configuration.nix
{ config, lib, pkgs, ... }:

let
  userKeysFile = config.sops.templates."user-api-keys.fish".path;
in
{
  sops.secrets = {
    anthropic_api_key.owner = "fluoride";
    vastai_api_key.owner = "fluoride";
    openrouter_api_key.owner = "fluoride";
    huggingface_token.owner = "fluoride";
  };

  sops.templates."user-api-keys.fish" = {
    owner = "fluoride";
    mode = "0400";
    content = ''
      set -gx ANTHROPIC_API_KEY "${config.sops.placeholder.anthropic_api_key}"
      set -gx VASTAI_API_KEY "${config.sops.placeholder.vastai_api_key}"
      set -gx OPENROUTER_API_KEY "${config.sops.placeholder.openrouter_api_key}"
      set -gx HF_TOKEN "${config.sops.placeholder.huggingface_token}"
    '';
  };

  home-manager.sharedModules = [
    {
      programs.fish.shellInit = lib.mkAfter ''
        # API keys from sops-nix (see modules/programs/secrets)
        if test -f ${userKeysFile}
          source ${userKeysFile}
        end
      '';
    }
  ];
}
