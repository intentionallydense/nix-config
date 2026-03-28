# Starship prompt — cross-platform.
# Used by: modules/home/default.nix
{ ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.starship = {
        enable = true;
        settings = {
          add_newline = false;
          scan_timeout = 10;
          format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$python$nix_shell$character";
          directory.style = "blue";
          character = {
            success_symbol = "[❯](purple)";
            error_symbol = "[❯](red)";
            vimcmd_symbol = "[❮](green)";
          };
          git_branch = {
            format = "[$branch]($style)";
            symbol = "git ";
            style = "bright-black";
          };
          git_status = {
            format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
            style = "cyan";
            conflicted = "​";
            untracked = "​";
            modified = "​";
            staged = "​";
            renamed = "​";
            deleted = "​";
            stashed = "≡";
          };
          git_state = {
            format = ''\([$state( $progress_current/$progress_total)]($style)\) '';
            style = "bright-black";
          };
          cmd_duration = {
            format = "[$duration]($style) ";
            style = "yellow";
          };
          nix_shell = {
            symbol = "❄️ ";
            format = "[$symbol]($style)";
          };
          python = {
            format = "[$virtualenv]($style) ";
            style = "bright-black";
            symbol = "py ";
          };
          rust.symbol = "rs ";
          golang.symbol = "go ";
          nodejs.symbol = "nodejs ";
          lua.symbol = "lua ";
          directory.read_only = " ro";
          package.symbol = "pkg ";
          docker_context.symbol = "docker ";
          aws.symbol = "aws ";
          azure.symbol = "az ";
          bun.symbol = "bun ";
          cmake.symbol = "cmake ";
          deno.symbol = "deno ";
          nim.symbol = "nim ";
          terraform.symbol = "terraform ";
          zig.symbol = "zig ";
          memory_usage.symbol = "memory ";
          purescript.symbol = "purs ";
          status.symbol = "[x](bold red) ";
          sudo.symbol = "sudo ";
          shell = {
            disabled = false;
            style = "cyan";
            bash_indicator = "";
            powershell_indicator = "";
          };
          os.symbols = {
            Macos = "mac ";
            NixOS = "nix ";
            Linux = "lnx ";
            Arch = "rch ";
            Ubuntu = "ubnt ";
            Fedora = "fed ";
            Windows = "win ";
            Unknown = "unk ";
          };
        };
      };
    })
  ];
}
