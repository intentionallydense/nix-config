# Hammerspoon — darwin only.
# Minecraft: scroll wheel -> render distance (F3+F up / F3+Shift+F down),
# always-on while the Prism-launched Java process is frontmost. The original
# scroll event is swallowed so the hotbar selection does NOT change.
#
# Karabiner can't trigger on mouse-wheel rotation (it can only emit scroll), so
# this lives here rather than next to the other Minecraft key rules in
# modules/darwin/karabiner. The app itself is installed via the homebrew cask
# "hammerspoon" (declared per-host). NB: Hammerspoon needs Accessibility
# permission granted manually once (System Settings > Privacy & Security >
# Accessibility) and "Launch at login" enabled in its menu bar — neither is
# nix-manageable (TCC / login items live outside the config).
#
# Used by: hosts/germanium/configuration.nix
{ ... }:
{
  home-manager.sharedModules = [
    ({ ... }: {
      home.file.".hammerspoon/init.lua" = {
        force = true;
        text = ''
          -- ~/.hammerspoon/init.lua — managed by nix-config (modules/darwin/hammerspoon).
          --
          -- Minecraft: scroll wheel adjusts render distance.
          --   scroll up   -> F3 + F         (render distance +1)
          --   scroll down -> F3 + Shift + F (render distance -1)
          -- Always-on while the Prism-launched Java process is frontmost; the
          -- original scroll event is swallowed, so the hotbar does NOT change.

          -- If the directions come out reversed, flip this.
          local SCROLL_UP_INCREASES = true

          -- Frontmost-app match, mirroring the Karabiner Minecraft rules: Prism
          -- runtimes live under PrismLauncher/java/, the Homebrew JDK under openjdk@21.
          local MC_PATH_PATTERNS = { "PrismLauncher/java", "openjdk@21" }

          local function minecraftFrontmost()
            local app = hs.application.frontmostApplication()
            if not app then return false end
            local path = app:path() or ""
            for _, pat in ipairs(MC_PATH_PATTERNS) do
              if string.find(path, pat, 1, true) then return true end
            end
            return false
          end

          -- Hold F3, tap F (optionally with Shift), release F3. F3 stays down
          -- across the F press so Minecraft treats it as a debug combo and does
          -- NOT toggle the debug screen. Shift is sent as a real key event so
          -- GLFW's hasShiftDown() registers it.
          local function f3f(withShift)
            local e = hs.eventtap.event
            e.newKeyEvent("f3", true):post()
            if withShift then e.newKeyEvent("shift", true):post() end
            e.newKeyEvent("f", true):post()
            e.newKeyEvent("f", false):post()
            if withShift then e.newKeyEvent("shift", false):post() end
            e.newKeyEvent("f3", false):post()
          end

          -- Globals (not locals) so Hammerspoon's GC doesn't collect the tap/timer.
          mcScroll = {}

          mcScroll.tap = hs.eventtap.new({ hs.eventtap.event.types.scrollWheel }, function(ev)
            if not minecraftFrontmost() then
              return false -- pass scroll through normally everywhere else
            end

            local dy = ev:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
            if dy == nil or dy == 0 then
              return false
            end

            local up = (dy > 0)
            if not SCROLL_UP_INCREASES then up = not up end

            f3f(not up) -- up -> no shift (increase); down -> shift (decrease)
            return true -- swallow the scroll so the hotbar doesn't move
          end)
          mcScroll.tap:start()

          -- macOS disables event taps on some events (e.g. secure input); re-arm.
          mcScroll.watchdog = hs.timer.doEvery(5, function()
            if mcScroll.tap and not mcScroll.tap:isEnabled() then mcScroll.tap:start() end
          end)

          hs.alert.show("Hammerspoon: Minecraft scroll -> render distance active")
        '';
      };
    })
  ];
}
