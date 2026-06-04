# Desktop GUI apps — the Linux equivalents of the germanium Homebrew casks
# Sylvia actually reaches for day-to-day. Imported by hosts/silicon/nixos.nix;
# add to other desktop hosts as needed.
{ ... }:
{
  home-manager.sharedModules = [
    (
      { pkgs, ... }:
      {
        home.packages = with pkgs; [
          beeper # chat aggregator (rolls up WhatsApp/Signal/etc. into one app)
          obsidian # notes — the Obsidian vaults
          zotero # reference manager
          vlc # media player
          picard # MusicBrainz Picard — music tagging
        ];
      }
    )
  ];
}
