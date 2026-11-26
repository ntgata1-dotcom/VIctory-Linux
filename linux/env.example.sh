# VIctory on Linux: copy to linux/env.sh (ignored by git) and fill in your paths.
# Everything here stays on your machine; nothing from the game goes into the repo.

# A Wine prefix of its own for VIctory (made by linux/setup-prefix.sh).
export WINEPREFIX="$HOME/.local/share/victory/prefix"
# vkd3d-proton (d3d12, d3d12core) and DXVK's dxgi from the prefix; no Mono or Gecko.
export WINEDLLOVERRIDES="d3d12,d3d12core,dxgi=n;mscoree,mshtml=;winedbg.exe=d"
export WINEDEBUG="fixme-all"
# Implicit Vulkan layers (overlays, capture tools) have crashed vkd3d-proton.
export VK_LOADER_LAYERS_DISABLE='~implicit~'
# With an integrated GPU as well, pick the discrete one by a part of its name
# (as `vulkaninfo --summary` prints it), e.g. 'RX 9070' or 'RTX 4070':
#export VKD3D_FILTER_DEVICE_NAME='RX 9070'
#export DXVK_FILTER_DEVICE_NAME='RX 9070'
export VKD3D_SHADER_CACHE_PATH="$HOME/.cache/victory/vkd3d"

# Where your own game files are, as a Windows path inside Wine (Z: is /).
export VICTORY_GAME_DIR='Z:\path\to\your\game'
export VICTORY_GAME_EXE='game_scarlett_master.exe'
# VIctory's cache and data (saves, settings, crashes.log): outside this repo.
export VICTORY_CACHE_DIR='Z:\home\you\.cache\victory'
export VICTORY_DATA_DIR='Z:\home\you\.local\share\victory\data'
