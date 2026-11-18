# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic game, section "Main": what a real game's Main section does (start the main loop).
# load_game.rb skips the section named "Main", as it does for real games.
rgss_main { raise 'Main must not run in the headless benchmark' }
