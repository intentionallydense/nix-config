# Invidious — privacy-respecting YouTube frontend, self-hosted on carbon.
# Accessed via Yattee (macOS/iOS) over Tailscale, using account-based
# subscription sync so the same sub list appears across devices.
#
# 2026 architecture note: Invidious has moved to a companion-based design.
# Video stream extraction now happens in `invidious-companion` (Deno app
# backed by youtube.js, actively maintained). The older `inv-sig-helper`
# is unmaintained upstream since 2025-07 and does not handle current
# YouTube player JS — we do NOT use it.
#
# Services:
#   - invidious (port 3001): web UI, account/sub management, feeds
#   - invidious-companion (127.0.0.1:8282, via podman): stream retrieval
#   - postgres "invidious" db (auto-provisioned alongside Immich's)
#
# Companion is pulled from quay.io/invidious/invidious-companion:latest
# because nixpkgs doesn't package it yet (Deno app). Updated by restarting
# the container, or by pinning a digest once stability matters.
#
# Access pattern: http://carbon:3001 over Tailscale. No HTTPS, no public
# domain — same as jellyfin (8096), immich (2283), grafana (3000).
# Companion's port is loopback-only; only invidious talks to it.
#
# The shared 16-char secret between Invidious and companion lives in
# /var/lib/invidious-companion/key (root-only, auto-generated on first
# boot). Two derivative files are written for the two services to read
# in their expected formats.
#
# Note: by upstream default the invidious service restarts every ~1h
# with ±5min jitter. Intentional, not a problem.
#
# Used by: carbon, tin.
{ config, pkgs, lib, ... }:
let
  stateDir = "/var/lib/invidious-companion";
  keyFile = "${stateDir}/key";
  invidiousExtraFile = "${stateDir}/invidious-extra.json";
  companionEnvFile = "${stateDir}/companion.env";
in
{
  # Cherry-picks for the cluster of YouTube schema changes that broke
  # channel/feed parsing in May 2026, plus one local fix on top:
  #
  #   1. KeyError "collectionThumbnailViewModel" — YouTube flattened
  #      playlist thumbnail nesting. (Issue #5516, merged as 99390d0.)
  #   2. Channel videos delivered as lockupViewModel (same wrapper as
  #      playlists), causing Invidious to misclassify videos as playlists
  #      with videoCount=-1. (Issue #5727, fixed by draft PR #5736 which
  #      adds VIDEO/PLAYLIST/PODCAST contentType discrimination.)
  #   3. PR #5736 ports a pre-existing pattern from ReelItem/Shorts
  #      parsers that sets `premiere_timestamp: Time.unix(0)` for all
  #      lockup-video entries. That's non-nil, so SearchVideo#upcoming?
  #      returns true, serializing as `"isUpcoming": true` for every
  #      channel video. API clients that filter upcoming premieres from
  #      feeds (Yattee) then drop every entry. Local patch sets it to
  #      nil instead, matching VideoRendererParser semantics.
  #   4. SearchVideo#to_json wraps the entire `authorThumbnails` field
  #      in an `if author_thumbnail` guard. Lockup-video entries have
  #      author_thumbnail=nil (YouTube omits the avatar in channel-tab
  #      lockups), so the field is omitted entirely from the response.
  #      Yattee silently filters entries that lack the field, leaving
  #      its subscription feed and channel pages blank even though the
  #      data is correct. Local patch moves the guard inside json.array
  #      so the field is always present (as `[]` when nil).
  #
  # The PR (#5736) is a DRAFT as of 2026-05-22 — pinned to commit
  # f684437754eb5a62529f4fd2b229af0430eb96da. If Fijxu force-pushes the
  # branch, our build is unaffected (we resolve to the exact commit), but
  # we should swap to the master commit hash once the PR merges.
  #
  # Note: PR #5736 applies on top of 99390d0 — both patches are required
  # together; the PR fails to apply on v2.20260207.0 alone. The local
  # isUpcoming patch then applies on top of both.
  #
  # Known residual gaps in this PR (per Fijxu's own description):
  #   - Channel podcasts won't appear (LOCKUP_CONTENT_TYPE_PODCAST is not
  #     yet handled).
  #   - Playlist "author" hyperlink shows update date instead of channel.
  #   - lengthSeconds=0 for all lockup-video entries (duration parsing
  #     in the new lockup shape isn't implemented yet). Cosmetic only —
  #     Yattee shows 0:00 in the duration overlay but plays fine.
  #
  # TODO: remove this overlay once nixpkgs ships a release containing
  # the upstream merged fixes (likely v2.2026xxxx.0 after May 2026).
  nixpkgs.overlays = [
    (final: prev: {
      invidious = prev.invidious.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (final.fetchpatch {
            name = "fix-collectionThumbnailViewModel-99390d0.patch";
            url = "https://github.com/iv-org/invidious/commit/99390d065d69bb451dea8aedf9a1bbaa52cddf2a.patch";
            hash = "sha256-fFyn00mOrSGygwZycJN6Su0p5ZaKMU/uqYrBFfVM1lQ=";
          })
          # VENDORED 2026-06-12: this was fetchpatch'd from the live PR URL
          # (github.com/iv-org/invidious/pull/5736.patch), but the draft branch
          # moved upstream and the hash drifted, breaking fresh builds (this is
          # what blocked invidious on tin). The file below is the byte-exact
          # original fetchpatch output (flat sha256-wFclJrc+NQqvY6PWwTj6DySSCc
          # tx616mL80iDVEOglI=), recovered from carbon's store and committed.
          ./fix-lockup-video-classification-pr5736.patch
          ./fix-lockup-video-not-upcoming.patch
          ./fix-author-thumbnails-emit-empty.patch
        ];
      });
    })
  ];

  # Shared-secret provisioner. Runs once at boot; regenerates the two
  # derivative files from the persistent key every time (cheap and
  # self-healing if someone mucks with them).
  systemd.services.invidious-companion-secret = {
    description = "Provision invidious-companion shared secret";
    wantedBy = [ "multi-user.target" ];
    before = [ "invidious.service" "podman-invidious-companion.service" ];
    path = [ pkgs.pwgen pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      mkdir -p ${stateDir}
      chmod 0755 ${stateDir}
      if [[ ! -s ${keyFile} ]]; then
        pwgen -s 16 1 > ${keyFile}
        chmod 0400 ${keyFile}
      fi
      key="$(cat ${keyFile})"
      printf '{"invidious_companion_key": "%s"}\n' "$key" > ${invidiousExtraFile}
      printf 'SERVER_SECRET_KEY=%s\n' "$key" > ${companionEnvFile}
      # World-readable: both files' secret is scoped to a private service
      # only reachable over Tailscale. Good enough; revisit if the threat
      # model changes.
      chmod 0644 ${invidiousExtraFile} ${companionEnvFile}
    '';
  };

  services.invidious = {
    enable = true;
    port = 3001;
    address = "0.0.0.0"; # Access gated by Tailscale firewall (carbon config)

    database.createLocally = true;

    # Deprecated in 2026 — companion replaces it. Explicit false for clarity.
    sig-helper.enable = false;

    # Injects {"invidious_companion_key": "..."} at service-start time.
    extraSettingsFile = invidiousExtraFile;

    settings = {
      # carbon's stateVersion is 23.11 → module defaults db.user = "kemal".
      # Override to match db.dbname ("invidious") required by the
      # database.createLocally assertion.
      db.user = "invidious";

      registration_enabled = true;
      login_enabled = true;
      # Captcha breaks API-based auth (Yattee can't solve it). Private
      # instance behind tailscale, no drive-by-signup threat — safe to
      # disable. Browser signup worked fine with captcha on because
      # Sylvia solved it manually; disabling it lets Yattee log in too.
      captcha_enabled = false;
      popular_enabled = false;
      statistics_enabled = false;
      https_only = false;

      # Points Invidious at the companion running in the podman container.
      # The path "/companion" matches companion's default SERVER_BASE_PATH.
      invidious_companion = [
        { private_url = "http://127.0.0.1:8282/companion"; }
      ];
    };
  };

  # Ensure secret is ready and companion is up before Invidious starts.
  systemd.services.invidious = {
    after = [
      "invidious-companion-secret.service"
      "podman-invidious-companion.service"
    ];
    wants = [ "podman-invidious-companion.service" ];
  };

  # Companion container — port exposed only on loopback.
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };
  virtualisation.oci-containers = {
    backend = "podman";
    containers.invidious-companion = {
      image = "quay.io/invidious/invidious-companion:latest";
      ports = [ "127.0.0.1:8282:8282" ];
      environmentFiles = [ companionEnvFile ];
      environment = {
        HOST = "0.0.0.0"; # bind inside the container; host-side only 127.0.0.1
        PORT = "8282";
      };
      autoStart = true;
    };
  };

  # Invidious (3001) is tailnet-only via trustedInterfaces — it binds 0.0.0.0
  # (address above) but the firewall only trusts tailscale0. (Removed
  # allowedTCPPorts = [ 3001 ] 2026-06-01; access is over Tailscale only.)
}
