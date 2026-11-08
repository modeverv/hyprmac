extension HyprConfig {
    public static let defaultText = #"""
# ~/.config/hyprmac/hyprmac.conf
# HyprMac — Hyprland-like tiling for macOS. Syntax follows hyprland.conf.
# The file is reloaded automatically when saved.

# ---------------------------------------------------------------
# Modifier
#   ALT (= Option) is the default because CMD+S / CMD+1..9 are used
#   by almost every Mac app (Save, tab switching ...).
#   For the exact Omarchy feel use:  $mod = SUPER   (SUPER = Command)
# ---------------------------------------------------------------
$mod = ALT
$terminal = open -na Terminal
$browser = open -a Safari

general {
    gaps_in = 5
    gaps_out = 10
}

# The special workspace (scratchpad) floats on top of any workspace.
special {
    scale = 0.85
}

# Commands run once when HyprMac starts
# exec-once = open -a Obsidian

# ---------------------------------------------------------------
# Window rules  (class: matches app name or bundle id, regex, case-insensitive)
# ---------------------------------------------------------------
windowrule = float, class:^(System Settings|System Preferences|Calculator|Archive Utility|Installer|Software Update)$
# Messaging apps live on the special workspace ($mod + S), like in Omarchy
windowrule = workspace special, class:^(Messages|Slack|Discord|LINE|Telegram|WhatsApp|Signal)$

# ---------------------------------------------------------------
# Key bindings  —  bind = MODS, KEY, DISPATCHER, ARG
# ---------------------------------------------------------------
bind = $mod, Return, exec, $terminal
bind = $mod SHIFT, B, exec, $browser
bind = $mod, W, killactive
bind = $mod, T, togglefloating
bind = $mod, F, fullscreen
bind = $mod, J, togglesplit
bind = $mod SHIFT, R, reload

# Move focus
bind = $mod, left, movefocus, l
bind = $mod, right, movefocus, r
bind = $mod, up, movefocus, u
bind = $mod, down, movefocus, d

# Swap windows (or push to the monitor in that direction)
bind = $mod SHIFT, left, swapwindow, l
bind = $mod SHIFT, right, swapwindow, r
bind = $mod SHIFT, up, swapwindow, u
bind = $mod SHIFT, down, swapwindow, d

# Resize the split of the active window
bind = $mod, minus, splitratio, -0.05
bind = $mod, equal, splitratio, +0.05

# Switch workspaces — instant, no animation
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod, 6, workspace, 6
bind = $mod, 7, workspace, 7
bind = $mod, 8, workspace, 8
bind = $mod, 9, workspace, 9
bind = $mod, 0, workspace, 10
bind = $mod, Tab, workspace, e+1
bind = $mod SHIFT, Tab, workspace, e-1
bind = $mod, grave, workspace, previous

# Move active window to a workspace (and follow it)
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod SHIFT, 6, movetoworkspace, 6
bind = $mod SHIFT, 7, movetoworkspace, 7
bind = $mod SHIFT, 8, movetoworkspace, 8
bind = $mod SHIFT, 9, movetoworkspace, 9
bind = $mod SHIFT, 0, movetoworkspace, 10

# Special workspace (scratchpad) — shows on top of the current workspace
bind = $mod, S, togglespecialworkspace
bind = $mod SHIFT, S, movetoworkspacesilent, special

# Monitors
bind = $mod, comma, focusmonitor, l
bind = $mod, period, focusmonitor, r
"""#
}
