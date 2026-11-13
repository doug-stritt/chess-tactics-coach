#!/bin/bash
set -euo pipefail

destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
cache="$PROJECT_TEMP_DIR/StockfishNetworks"
mkdir -p "$destination" "$cache"

install_network() {
    local hash="$1"
    local name="nn-${hash:0:12}.nnue"
    local network="$cache/$name"
    if [[ ! -f "$network" ]] || ! printf '%s  %s\n' "$hash" "$network" | shasum -a 256 -c --status; then
        curl -fsSL --retry 2 --connect-timeout 15 --max-time 180 \
            "https://tests.stockfishchess.org/api/nn/$name" -o "$network.download"
        printf '%s  %s\n' "$hash" "$network.download" | shasum -a 256 -c
        mv "$network.download" "$network"
    fi
    cp "$network" "$destination/$name"
}

install_network c288c895ea924429ea9092e3f36b2b3c1f00f2a3a4c759ff7e57e79e3b43e4a7
install_network 37f18f62d772f3107e1d6aaca3898c130c3c86f2ab63e6555fbbca20635a899d
