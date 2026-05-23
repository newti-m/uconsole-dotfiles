#!/bin/bash

command -v fzf &> /dev/null || { echo "Requires fzf: sudo apt install fzf"; exit 1; }

HEIGHT=22
LOGFILE="/tmp/fzf-system-manager.log"
FZF_OPTS=(--height="$HEIGHT" --border=rounded --cycle --info=inline)

set -u

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
log "Script started"

trap 'rm -f /tmp/fzf-system-manager.*.tmp 2>/dev/null' EXIT

# ── fzf wrappers ──────────────────────────────────────────────────────────────

menu_pick() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | fzf "${FZF_OPTS[@]}" --prompt " $prompt  " --expect=left,esc
}

item_pick() {
    local prompt="$1" preview="$2"; shift 2
    printf '%s\n' "↩ back" "$@" \
        | fzf "${FZF_OPTS[@]}" --prompt " $prompt  " \
              --preview-window=right:55%:wrap --preview "$preview" \
              --expect=left,esc
}

action_pick() {
    local prompt="$1"; shift
    printf '%s\n' "↩ back" "$@" \
        | fzf "${FZF_OPTS[@]}" --prompt " $prompt  " --expect=left,esc
}

# Parse fzf output: first line = key, last line = selection
fzf_key()  { head -1 <<< "$1"; }
fzf_sel()  { tail -1 <<< "$1"; }
is_back()  { local k="$1" s="$2"; [[ "$k" == "left" || "$k" == "esc" || "$s" == "↩ back" || -z "$s" ]]; }

# ── WiFi helpers ──────────────────────────────────────────────────────────────

wifi_check() { command -v nmcli &>/dev/null || { echo "nmcli not found (NetworkManager required)"; return 1; }; }

# nmcli terse output escapes literal colons as \: — replace them with a
# placeholder before splitting on : so SSIDs containing colons parse correctly.
_nmcli_unescape() { sed 's/\\:/\x01/g'; }

wifi_scan() {
    # Output format per line: "SIGNAL_BAR LOCK\tSSID"
    # Tab separates the visual prefix from the raw SSID so callers can extract it.
    nmcli -t -f SSID,SIGNAL,SECURITY device wifi list --rescan yes 2>/dev/null \
        | grep -v '^:' \
        | _nmcli_unescape \
        | awk -F: 'NF>=2 && $1!="" {
            gsub(/\x01/, ":", $1)
            sig = $2 + 0
            bar = (sig>=80 ? "▰▰▰▰▰" : sig>=60 ? "▰▰▰▰▱" : sig>=40 ? "▰▰▰▱▱" : sig>=20 ? "▰▰▱▱▱" : "▰▱▱▱▱")
            sec = ($3=="" || $3=="--") ? "  " : "🔒"
            printf "%03d\t%s %s %s\t%s\n", sig, bar, sec, $1, $1
          }' \
        | sort -t$'\t' -k1 -rn \
        | awk -F'\t' '{print $2 "\t" $3}' \
        | awk -F'\t' '!seen[$2]++'
}

wifi_saved() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | _nmcli_unescape \
        | awk -F: '$2=="802-11-wireless" {gsub(/\x01/,":",$1); print $1}' \
        | sort
}

wifi_active_ssid() {
    nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null \
        | _nmcli_unescape \
        | awk -F: '$1=="yes" {gsub(/\x01/,":",$2); print $2; exit}'
}

# Returns the NM connection ID whose SSID matches, or empty if none
wifi_conn_by_ssid() {
    nmcli -t -f NAME,802-11-wireless.ssid connection show 2>/dev/null \
        | _nmcli_unescape \
        | awk -F: -v s="$1" '$2==s {gsub(/\x01/,":",$1); print $1; exit}'
}

# mode: "saved" | "open" | "save" | "nosave"
wifi_connect() {
    local ssid="$1" mode="$2"
    local password conn_id

    case "$mode" in
    saved)
        conn_id=$(wifi_conn_by_ssid "$ssid")
        if [[ -z "$conn_id" ]]; then
            echo "No saved profile for '$ssid'."; return 1
        fi
        echo "Using saved profile for '$ssid'..."
        log "wifi: up saved '$ssid' (conn=$conn_id)"
        nmcli connection up "$conn_id"
        ;;
    open)
        echo "Connecting to open network '$ssid'..."
        log "wifi: open connect '$ssid'"
        nmcli device wifi connect "$ssid"
        ;;
    save|nosave)
        read -rsp " Password for '$ssid': " password; echo ""
        if [[ -z "$password" ]]; then echo "Cancelled."; return 1; fi
        log "wifi: secured connect '$ssid' (mode=$mode)"
        nmcli device wifi connect "$ssid" password "$password"
        unset password
        if [[ "$mode" == "nosave" ]]; then
            # nmcli device wifi connect always creates a profile; find it by SSID
            # and mark it non-autoconnect so it won't reconnect automatically
            conn_id=$(wifi_conn_by_ssid "$ssid")
            [[ -n "$conn_id" ]] && nmcli connection modify "$conn_id" connection.autoconnect no
        fi
        ;;
    esac
}

wifi_forget() {
    local name="$1"
    echo "Deleting saved connection '$name'..."
    log "wifi: forget '$name'"
    nmcli connection delete "$name"
}

wifi_disconnect() {
    local ssid
    ssid=$(wifi_active_ssid)
    if [[ -z "$ssid" ]]; then
        echo "Not connected to any WiFi network."; return
    fi
    local dev
    dev=$(nmcli -t -f DEVICE,TYPE device status | _nmcli_unescape \
        | awk -F: '$2=="wifi"{gsub(/\x01/,":",$1); print $1; exit}')
    if [[ -z "$dev" ]]; then echo " No wifi device found."; return; fi
    echo "Disconnecting from '$ssid'..."
    log "wifi: disconnect '$ssid' via $dev"
    nmcli device disconnect "$dev"
}

# ── WireGuard helpers ─────────────────────────────────────────────────────────

wg_interfaces() {
    {
        sudo wg show interfaces 2>/dev/null | tr ' ' '\n'
        systemctl list-units --type=service --all --no-legend 2>/dev/null \
            | awk '{print $1}' | grep '^wg-quick@' \
            | sed 's/^wg-quick@//; s/\.service$//'
        sudo ls /etc/wireguard/ 2>/dev/null | grep '\.conf$' | sed 's/\.conf$//'
    } | grep -E '^[A-Za-z0-9_=+.-]{1,15}$' | sort -u
}

# ── Bluetooth helpers ────────────────────────────────────────────────────────

bt_check() { command -v bluetoothctl &>/dev/null || { echo "bluetoothctl not found (install bluez)"; return 1; }; }

bt_list() {
    # Output per line: "STATUS NAME\tMAC"
    # Use interactive pipe mode so bluetoothd's full device cache is queried,
    # including devices discovered but not yet paired.
    printf 'devices\nquit\n' | bluetoothctl 2>/dev/null \
    | grep '^Device ' \
    | while IFS= read -r line; do
        local mac name info connected paired
        mac=$(awk '{print $2}' <<< "$line")
        name=$(awk '{$1=$2=""; sub(/^ */,""); print}' <<< "$line")
        info=$(bluetoothctl info "$mac" 2>/dev/null)
        connected=$(awk '/^[[:space:]]+Connected:/{print $2}' <<< "$info")
        paired=$(awk '/^[[:space:]]+Paired:/{print $2}' <<< "$info")
        if [[ "$connected" == "yes" ]]; then
            printf '● %-40s\t%s\n' "$name" "$mac"
        elif [[ "$paired" == "yes" ]]; then
            printf '○ %-40s\t%s\n' "$name" "$mac"
        else
            printf '  %-40s\t%s\n' "$name" "$mac"
        fi
    done
}

# ── Spotify helper ────────────────────────────────────────────────────────────

_spotify_cmd() {
    local player cmd="$1"
    player=$(playerctl -l 2>/dev/null | grep -i ncspot | head -1)
    if [[ -z "$player" ]]; then
        echo " ncspot not running"
        read -rp " Press Enter to continue..." _ </dev/tty
        return
    fi
    log "spotify: $cmd"
    playerctl -p "$player" "$cmd" 2>/dev/null
}

# ── Category handlers ─────────────────────────────────────────────────────────

handle_systemd() {
    local user_flag="$1"  # "--user" or ""
    local label="$2"
    local sctl actions items result key selected action target

    sctl=(systemctl)
    [[ -n "$user_flag" ]] && sctl+=(--user)
    actions=("status" "start" "stop" "restart" "enable" "disable" "reload-or-restart" "kill")

    while true; do
        items=$("${sctl[@]}" list-units --type=service --all --no-legend 2>/dev/null \
            | awk '{print $1}' | grep -v '●' | grep -v '^$' \
            | sed 's/\.service$//' | sort)
        [[ -z "$items" ]] && { echo "No services found."; read -rp " Press Enter to continue..." _ </dev/tty; return; }

        local preview="${sctl[*]} status {1}.service 2>&1 | head -25"
        local items_arr; mapfile -t items_arr <<< "$items"
        result=$(item_pick "$label" "$preview" "${items_arr[@]}")
        key=$(fzf_key "$result"); selected=$(fzf_sel "$result")
        is_back "$key" "$selected" && return

        result=$(action_pick "$selected action" "${actions[@]}")
        key=$(fzf_key "$result"); action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        target="${selected}.service"
        echo ""
        echo " ▶ ${sctl[*]} $action $target"
        log "exec: ${sctl[*]} $action $target"
        "${sctl[@]}" "$action" "$target"
        echo ""; read -rp " Press Enter to continue..." _ </dev/tty
    done
}

handle_processes() {
    local result key selected action pid

    while true; do
        local items
        items=$(ps -eo comm= --no-headers 2>/dev/null \
            | sort -u | grep -v '^$' | grep -v '^\[' | head -150)

        local items_arr; mapfile -t items_arr <<< "$items"
        result=$(item_pick "running processes" "ps aux | grep -F {1} | grep -v grep" "${items_arr[@]}")
        key=$(fzf_key "$result"); selected=$(fzf_sel "$result")
        is_back "$key" "$selected" && return

        result=$(action_pick "$selected signal" "TERM" "KILL" "HUP" "STOP" "CONT")
        key=$(fzf_key "$result"); action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        mapfile -t pids < <(ps -eo pid,comm= | awk -v c="$selected" '$2==c {print $1}')
        if [[ ${#pids[@]} -gt 0 ]]; then
            echo ""; echo " ▶ kill -$action ${pids[*]} ($selected)"
            log "kill -$action ${pids[*]} ($selected)"
            kill -"$action" "${pids[@]}"
        else
            echo " Process not found: $selected"
            log "process not found: $selected"
        fi
        echo ""; read -rp " Press Enter to continue..." _ </dev/tty
    done
}

handle_docker() {
    command -v docker &>/dev/null || { echo "Docker not available."; read -rp " Press Enter to continue..." _ </dev/tty; return; }
    local actions=("start" "stop" "restart" "pause" "unpause" "logs" "rm")
    local result key selected action

    while true; do
        local items
        items=$(docker ps -a --format '{{.Names}}{{"\t"}}{{.Status}}' 2>/dev/null | column -t | sort)
        [[ -z "$items" ]] && { echo "No containers found."; read -rp " Press Enter to continue..." _ </dev/tty; return; }

        local items_arr; mapfile -t items_arr <<< "$items"
        result=$(item_pick "docker containers" "docker inspect {1} 2>&1 | head -30" "${items_arr[@]}")
        key=$(fzf_key "$result"); selected=$(fzf_sel "$result")
        is_back "$key" "$selected" && return
        selected=$(awk '{print $1}' <<< "$selected")  # strip status column

        result=$(action_pick "$selected action" "${actions[@]}")
        key=$(fzf_key "$result"); action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        echo ""; echo " ▶ docker $action $selected"
        log "docker $action $selected"
        if [[ "$action" == "logs" ]]; then
            docker logs --tail=50 "$selected" 2>&1 | less
        else
            docker "$action" "$selected"
        fi
        echo ""; read -rp " Press Enter to continue..." _ </dev/tty
    done
}

handle_wireguard() {
    command -v wg &>/dev/null || { echo "wg not found (install wireguard-tools)"; read -rp " Press Enter to continue..." _ </dev/tty; return; }
    # Ensure sudo credentials are cached before any fzf opens — avoids a
    # password prompt appearing mid-menu or inside a preview pane.
    sudo -n true 2>/dev/null || { echo " WireGuard requires sudo. Authenticating..."; sudo true || return; }

    while true; do
        local ifaces
        mapfile -t ifaces < <(wg_interfaces)
        [[ ${#ifaces[@]} -eq 0 ]] && { echo " No WireGuard interfaces found."; read -rp " Press Enter to continue..." _ </dev/tty; return; }

        local active
        active=$(sudo wg show interfaces 2>/dev/null)

        local entries=()
        for iface in "${ifaces[@]}"; do
            grep -qw "$iface" <<< "$active" \
                && entries+=("● UP   $iface") \
                || entries+=("○ DOWN $iface")
        done

        # {-1} = last whitespace-delimited field = interface name
        # sudo -n: non-interactive — never prompts; prints nothing if not cached
        local preview="sudo -n wg show {-1} 2>/dev/null || echo '(not active)'"
        local result key picked
        result=$(item_pick "wireguard" "$preview" "${entries[@]}")
        key=$(fzf_key "$result"); picked=$(fzf_sel "$result")
        is_back "$key" "$picked" && return

        local iface; iface=$(awk '{print $NF}' <<< "$picked")
        local is_up=false
        grep -qw "$iface" <<< "$active" && is_up=true

        local toggle_label; $is_up && toggle_label="disconnect" || toggle_label="connect"

        result=$(action_pick "$iface" "$toggle_label" "status" "show config")
        key=$(fzf_key "$result"); local action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        echo ""
        case "$action" in
        "connect")
            echo " ▶ sudo wg-quick up $iface"
            log "wg: up $iface"
            sudo wg-quick up "$iface"
            ;;
        "disconnect")
            echo " ▶ sudo wg-quick down $iface"
            log "wg: down $iface"
            sudo wg-quick down "$iface"
            ;;
        "status")
            sudo wg show "$iface" 2>&1 || echo " Interface not active."
            ;;
        "show config")
            sudo grep -vE '^\s*(PrivateKey|PresharedKey)\s*=' \
                /etc/wireguard/"$iface".conf 2>&1 | less
            ;;
        esac
        echo ""; read -rp " Press Enter to continue..." _ </dev/tty
    done
}

handle_wifi() {
    wifi_check || { read -rp " Press Enter to continue..." _ </dev/tty; return; }

    local wifi_actions=("scan & connect" "saved networks" "disconnect" "show status")

    while true; do
        local result key choice
        result=$(menu_pick "wifi" "${wifi_actions[@]}")
        key=$(fzf_key "$result"); choice=$(fzf_sel "$result")
        is_back "$key" "$choice" && return

        case "$choice" in
        "scan & connect")
            echo " Scanning for networks..."
            local scan_out ssid_entries
            scan_out=$(wifi_scan)
            [[ -z "$scan_out" ]] && { echo " No networks found."; read -rp " Press Enter to continue..." _ </dev/tty; continue; }
            mapfile -t ssid_entries <<< "$scan_out"

            # field 1 = "BAR ICON SSID" (display), field 2 = raw SSID
            result=$(printf '%s\n' "${ssid_entries[@]}" \
                | fzf "${FZF_OPTS[@]}" --prompt " select network  " \
                      --delimiter=$'\t' --with-nth=1 --expect=left,esc)
            key=$(fzf_key "$result"); local picked=$(fzf_sel "$result")
            is_back "$key" "$picked" && continue
            local ssid; ssid=$(cut -f2 <<< "$picked")

            # Determine connect mode without any raw prompts
            local mode saved_conn
            saved_conn=$(wifi_conn_by_ssid "$ssid")
            if [[ -n "$saved_conn" ]]; then
                mode="saved"
            elif [[ "$picked" != *"🔒"* ]]; then
                mode="open"
            else
                result=$(action_pick "connect '$ssid'" "connect & save" "connect (no save)")
                key=$(fzf_key "$result"); local save_pick=$(fzf_sel "$result")
                is_back "$key" "$save_pick" && continue
                [[ "$save_pick" == "connect & save" ]] && mode="save" || mode="nosave"
            fi

            echo ""
            wifi_connect "$ssid" "$mode"
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        "saved networks")
            local saved saved_arr
            saved=$(wifi_saved)
            [[ -z "$saved" ]] && { echo " No saved networks."; read -rp " Press Enter to continue..." _ </dev/tty; continue; }
            mapfile -t saved_arr <<< "$saved"

            result=$(action_pick "saved networks" "${saved_arr[@]}")
            key=$(fzf_key "$result"); local net=$(fzf_sel "$result")
            is_back "$key" "$net" && continue

            result=$(action_pick "'$net' action" "connect" "forget")
            key=$(fzf_key "$result"); local net_action=$(fzf_sel "$result")
            is_back "$key" "$net_action" && continue

            if [[ "$net_action" == "forget" ]]; then
                result=$(action_pick "delete '$net'?" "yes, delete" "cancel")
                key=$(fzf_key "$result"); local confirm=$(fzf_sel "$result")
                is_back "$key" "$confirm" && continue
                [[ "$confirm" != "yes, delete" ]] && continue
            fi

            echo ""
            case "$net_action" in
            "connect") nmcli connection up "$net" ;;
            "forget")  wifi_forget "$net" ;;
            esac
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        "disconnect")
            echo ""
            wifi_disconnect
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        "show status")
            echo ""
            nmcli device wifi 2>/dev/null || nmcli device status
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        esac
    done
}

handle_bluetooth() {
    bt_check || { read -rp " Press Enter to continue..." _ </dev/tty; return; }

    local bt_menu=("devices" "scan for new devices" "controller info")

    while true; do
        local result key choice
        result=$(menu_pick "bluetooth" "${bt_menu[@]}")
        key=$(fzf_key "$result"); choice=$(fzf_sel "$result")
        is_back "$key" "$choice" && return

        case "$choice" in
        "devices"|"scan for new devices")
            if [[ "$choice" == "scan for new devices" ]]; then
                echo " Scanning for 8 seconds..."
                # Interactive pipe: keeps bluetoothctl alive for the full scan
                # so bluetoothd properly registers discovered devices in its cache
                { printf 'scan on\n'; sleep 8; printf 'scan off\nquit\n'; } \
                    | bluetoothctl &>/dev/null
            fi

            local dev_out dev_entries
            dev_out=$(bt_list)
            [[ -z "$dev_out" ]] && { echo " No devices found."; read -rp " Press Enter to continue..." _ </dev/tty; continue; }
            mapfile -t dev_entries <<< "$dev_out"

            # field 1 = "STATUS NAME" (display), field 2 = MAC (identifier)
            result=$(printf '%s\n' "${dev_entries[@]}" \
                | fzf "${FZF_OPTS[@]}" --prompt " select device  " \
                      --delimiter=$'\t' --with-nth=1 \
                      --preview='bluetoothctl info {2} 2>&1' \
                      --preview-window=right:55%:wrap \
                      --expect=left,esc)
            key=$(fzf_key "$result"); local picked=$(fzf_sel "$result")
            is_back "$key" "$picked" && continue

            local mac; mac=$(cut -f2 <<< "$picked")
            local dev_info; dev_info=$(bluetoothctl info "$mac" 2>/dev/null)
            local connected paired
            connected=$(awk '/^[[:space:]]+Connected:/{print $2}' <<< "$dev_info")
            paired=$(awk '/^[[:space:]]+Paired:/{print $2}' <<< "$dev_info")

            local actions=()
            [[ "$connected" == "yes" ]] && actions+=("disconnect") || actions+=("connect")
            [[ "$paired" != "yes" ]]    && actions+=("pair")
            actions+=("trust" "remove" "info")

            result=$(action_pick "$mac" "${actions[@]}")
            key=$(fzf_key "$result"); local action=$(fzf_sel "$result")
            is_back "$key" "$action" && continue

            echo ""
            echo " ▶ bluetoothctl $action $mac"
            log "bt: $action $mac"
            case "$action" in
            connect)    bluetoothctl connect    "$mac" ;;
            disconnect) bluetoothctl disconnect "$mac" ;;
            pair)
                echo " Pairing $mac — confirm any passkey prompt below:"
                # Register agent so PIN/passkey prompts go through bluetoothctl
                # rather than appearing as raw kernel/udev prompts
                { printf 'agent on\ndefault-agent\npair %s\n' "$mac"
                  sleep 30
                  printf 'quit\n'
                } | bluetoothctl
                ;;
            trust)      bluetoothctl trust      "$mac" ;;
            remove)     bluetoothctl remove     "$mac" ;;
            info)       bluetoothctl info       "$mac" ;;
            esac
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        "controller info")
            echo ""
            bluetoothctl show 2>&1
            echo ""; read -rp " Press Enter to continue..." _ </dev/tty
            ;;
        esac
    done
}

handle_spotify() {
    command -v ncspot &>/dev/null || {
        echo " ncspot not found. Install from https://github.com/hrkfdn/ncspot/releases"
        read -rp " Press Enter to continue..." _ </dev/tty
        return
    }
    command -v playerctl &>/dev/null || {
        echo " playerctl not found. Install with: sudo apt install playerctl"
        read -rp " Press Enter to continue..." _ </dev/tty
        return
    }

    while true; do
        local tmpstat; tmpstat=$(mktemp /tmp/fzf-system-manager.XXXXXX.tmp)
        {
            local player
            player=$(playerctl -l 2>/dev/null | grep -i ncspot | head -1)
            if [[ -n "$player" ]] && playerctl -p "$player" status &>/dev/null; then
                local status title artist album pos dur
                status=$(playerctl -p "$player" status 2>/dev/null)
                title=$(playerctl -p "$player" metadata title 2>/dev/null || echo "—")
                artist=$(playerctl -p "$player" metadata artist 2>/dev/null || echo "—")
                album=$(playerctl -p "$player" metadata album 2>/dev/null || echo "—")
                pos=$(playerctl -p "$player" position 2>/dev/null \
                    | awk '{m=int($1/60); s=int($1%60); printf "%d:%02d", m, s}')
                dur=$(playerctl -p "$player" metadata mpris:length 2>/dev/null \
                    | awk '{m=int($1/1000000/60); s=int($1/1000000%60); printf "%d:%02d", m, s}')
                printf ' status:  %s\n' "$status"
                printf ' track:   %s\n' "$title"
                printf ' artist:  %s\n' "$artist"
                printf ' album:   %s\n' "$album"
                [[ -n "$pos" && -n "$dur" ]] && printf ' pos:     %s / %s\n' "$pos" "$dur"
            else
                printf ' ncspot not running\n\n launch "open ncspot" to start\n'
            fi
        } > "$tmpstat"

        local result key choice
        result=$(printf '↩ back\nopen ncspot\nplay/pause\nnext\nprev\nstop\n' \
            | fzf "${FZF_OPTS[@]}" --prompt " spotify  " \
                  --preview="cat \"$tmpstat\"" \
                  --preview-window=up:8:wrap \
                  --expect=left,esc)

        rm -f "$tmpstat"
        key=$(fzf_key "$result"); choice=$(fzf_sel "$result")
        is_back "$key" "$choice" && return

        local player
        player=$(playerctl -l 2>/dev/null | grep -i ncspot | head -1)

        case "$choice" in
        "open ncspot")
            log "spotify: launch ncspot"
            ncspot
            ;;
        "play/pause")
            _spotify_cmd play-pause
            ;;
        "next")
            _spotify_cmd next
            ;;
        "prev")
            _spotify_cmd previous
            ;;
        "stop")
            _spotify_cmd stop
            ;;
        esac
        [[ "$choice" != "open ncspot" ]] && sleep 0.3
    done
}

handle_netstatus() {
    while true; do
        local wifi_ssid wifi_signal wifi_bar wifi_line int_lines ext_ip

        wifi_ssid=$(wifi_active_ssid)
        if [[ -n "$wifi_ssid" ]]; then
            wifi_signal=$(nmcli -t -f ACTIVE,SIGNAL device wifi 2>/dev/null \
                | awk -F: '$1=="yes"{print $2; exit}')
            wifi_signal=${wifi_signal:-0}
            wifi_bar=$(awk -v s="$wifi_signal" 'BEGIN{
                if      (s>=80) b="▰▰▰▰▰"
                else if (s>=60) b="▰▰▰▰▱"
                else if (s>=40) b="▰▰▰▱▱"
                else if (s>=20) b="▰▰▱▱▱"
                else            b="▰▱▱▱▱"
                print b
            }')
            wifi_line="$wifi_ssid  $wifi_bar  (${wifi_signal}%)"
        else
            wifi_line="not connected"
        fi

        int_lines=$(ip -4 addr show 2>/dev/null \
            | awk '/inet /{
                split($2,a,"/"); iface=$NF
                if (iface!="lo") printf "   %-12s %s\n", iface":", a[1]
            }')

        if command -v curl &>/dev/null; then
            ext_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
                     || echo "unavailable")
        else
            ext_ip="curl not installed"
        fi

        # Write status to a temp file so fzf can display it in its own
        # preview pane — avoids content printing above/off the fzf window.
        local tmpstat; tmpstat=$(mktemp /tmp/fzf-system-manager.XXXXXX.tmp)
        {
            printf ' wifi:         %s\n\n' "$wifi_line"
            printf ' internal:\n%s\n\n' "$int_lines"
            printf ' external:     %s\n' "$ext_ip"
        } > "$tmpstat"

        local result key choice
        result=$(printf '↩ back\nrefresh\n' \
            | fzf "${FZF_OPTS[@]}" --prompt " network status  " \
                  --preview="cat \"$tmpstat\"" \
                  --preview-window=up:9:wrap \
                  --expect=left,esc)

        rm -f "$tmpstat"
        key=$(fzf_key "$result"); choice=$(fzf_sel "$result")
        is_back "$key" "$choice" && return
        # "refresh" selected: loop again, regenerate data
    done
}

# ── Main loop ─────────────────────────────────────────────────────────────────

CATEGORIES=("system services" "user services" "running processes" "docker containers" "wifi" "wireguard" "bluetooth" "network status" "spotify")

while true; do
    result=$(menu_pick "category" "${CATEGORIES[@]}")
    key=$(fzf_key "$result"); category=$(fzf_sel "$result")
    is_back "$key" "$category" && { echo " Exited."; log "exit"; exit 0; }
    log "category: $category"

    case "$category" in
    "system services")   handle_systemd ""       "system services" ;;
    "user services")     handle_systemd "--user" "user services"   ;;
    "running processes") handle_processes ;;
    "docker containers") handle_docker    ;;
    "wifi")              handle_wifi       ;;
    "wireguard")         handle_wireguard  ;;
    "bluetooth")         handle_bluetooth  ;;
    "network status")    handle_netstatus  ;;
    "spotify")           handle_spotify    ;;
    esac
done
