#!/bin/bash

command -v fzf &> /dev/null || { echo "Requires fzf: sudo apt install fzf"; exit 1; }

HEIGHT=22
LOGFILE="/tmp/fzf-system-manager.log"
FZF_OPTS=(--height="$HEIGHT" --border=rounded --cycle --info=inline)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
log "Script started"

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

# mode: "saved" | "open" | "save" | "nosave"
wifi_connect() {
    local ssid="$1" mode="$2"
    local password

    case "$mode" in
    saved)
        echo "Using saved profile for '$ssid'..."
        log "wifi: up saved '$ssid'"
        nmcli connection up "$ssid"
        ;;
    open)
        echo "Connecting to open network '$ssid'..."
        log "wifi: open connect '$ssid'"
        nmcli device wifi connect "$ssid"
        ;;
    save|nosave)
        read -rsp " Password for '$ssid': " password; echo ""
        [[ -z "$password" ]] && { echo "Cancelled."; return 1; }
        log "wifi: secured connect '$ssid' (mode=$mode)"
        if [[ "$mode" == "save" ]]; then
            nmcli device wifi connect "$ssid" password "$password"
        else
            nmcli device wifi connect "$ssid" password "$password" -- \
                connection.autoconnect no 2>/dev/null \
            || nmcli device wifi connect "$ssid" password "$password"
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
    echo "Disconnecting from '$ssid'..."
    log "wifi: disconnect '$ssid'"
    nmcli device disconnect "$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi' | cut -d: -f1 | head -1)"
}

# ── WireGuard helpers ─────────────────────────────────────────────────────────

wg_interfaces() {
    {
        sudo wg show interfaces 2>/dev/null | tr ' ' '\n'
        systemctl list-units --type=service --all --no-legend 2>/dev/null \
            | awk '{print $1}' | grep '^wg-quick@' \
            | sed 's/^wg-quick@//; s/\.service$//'
        sudo ls /etc/wireguard/ 2>/dev/null | grep '\.conf$' | sed 's/\.conf$//'
    } | grep -v '^$' | sort -u
}

# ── Category handlers ─────────────────────────────────────────────────────────

handle_systemd() {
    local user_flag="$1"  # "--user" or ""
    local label="$2"
    local cmd_prefix actions items result key selected action target

    [[ -n "$user_flag" ]] && cmd_prefix="systemctl --user" || cmd_prefix="sudo systemctl"
    actions=("status" "start" "stop" "restart" "enable" "disable" "reenable" "kill")

    while true; do
        items=$(systemctl $user_flag list-units --type=service --all --no-legend 2>&1 \
            | awk '{print $1}' | grep -v '[●@]' | grep -v '^$' \
            | sed 's/\.service$//' | sort)
        [[ -z "$items" ]] && { echo "No services found."; read -r; return; }

        local preview="systemctl $user_flag status {1}.service 2>&1 | head -25"
        local items_arr; mapfile -t items_arr <<< "$items"
        result=$(item_pick "$label" "$preview" "${items_arr[@]}")
        key=$(fzf_key "$result"); selected=$(fzf_sel "$result")
        is_back "$key" "$selected" && return

        result=$(action_pick "$selected action" "${actions[@]}")
        key=$(fzf_key "$result"); action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        target="${selected}.service"
        echo ""
        echo " ▶ $cmd_prefix $action $target"
        log "exec: $cmd_prefix $action $target"
        $cmd_prefix "$action" "$target"
        echo ""; read -rp " Press Enter to continue..." _
    done
}

handle_processes() {
    local result key selected pid

    while true; do
        local items
        items=$(ps aux --no-headers 2>&1 \
            | awk '{print $11}' | sort -u | grep -v '^$' | grep -v '^\[' | head -150)

        local items_arr; mapfile -t items_arr <<< "$items"
        result=$(item_pick "running processes" "ps aux | grep -F {1} | grep -v grep" "${items_arr[@]}")
        key=$(fzf_key "$result"); selected=$(fzf_sel "$result")
        is_back "$key" "$selected" && return

        result=$(action_pick "$selected signal" "TERM" "KILL" "HUP" "STOP" "CONT")
        key=$(fzf_key "$result"); action=$(fzf_sel "$result")
        is_back "$key" "$action" && continue

        pid=$(ps aux | grep -F "$selected" | grep -v grep | awk 'NR==1{print $2}')
        if [[ -n "$pid" ]]; then
            echo ""; echo " ▶ kill -$action $pid ($selected)"
            log "kill -$action $pid ($selected)"
            kill -"$action" "$pid"
        else
            echo " Process not found: $selected"
            log "process not found: $selected"
        fi
        echo ""; read -rp " Press Enter to continue..." _
    done
}

handle_docker() {
    command -v docker &>/dev/null || { echo "Docker not available."; read -r; return; }
    local actions=("start" "stop" "restart" "pause" "unpause" "logs" "rm")
    local result key selected action

    while true; do
        local items
        items=$(docker ps -a --format '{{.Names}}\t{{.Status}}' 2>&1 | column -t | sort)
        [[ -z "$items" ]] && { echo "No containers found."; read -r; return; }

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
        echo ""; read -rp " Press Enter to continue..." _
    done
}

handle_wireguard() {
    command -v wg &>/dev/null || { echo "wg not found (install wireguard-tools)"; read -r; return; }

    while true; do
        local ifaces
        mapfile -t ifaces < <(wg_interfaces)
        [[ ${#ifaces[@]} -eq 0 ]] && { echo " No WireGuard interfaces found."; read -r; return; }

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
            sudo cat /etc/wireguard/"$iface".conf 2>&1
            ;;
        esac
        echo ""; read -rp " Press Enter to continue..." _
    done
}

handle_wifi() {
    wifi_check || { read -r; return; }

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
            [[ -z "$scan_out" ]] && { echo " No networks found."; read -r; continue; }
            mapfile -t ssid_entries <<< "$scan_out"

            # field 1 = "BAR ICON SSID" (display), field 2 = raw SSID
            result=$(printf '%s\n' "${ssid_entries[@]}" \
                | fzf "${FZF_OPTS[@]}" --prompt " select network  " \
                      --delimiter=$'\t' --with-nth=1 --expect=left,esc)
            key=$(fzf_key "$result"); local picked=$(fzf_sel "$result")
            is_back "$key" "$picked" && continue
            local ssid; ssid=$(cut -f2 <<< "$picked")

            # Determine connect mode without any raw prompts
            local mode
            if nmcli connection show "$ssid" &>/dev/null; then
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
            echo ""; read -rp " Press Enter to continue..." _
            ;;
        "saved networks")
            local saved saved_arr
            saved=$(wifi_saved)
            [[ -z "$saved" ]] && { echo " No saved networks."; read -r; continue; }
            mapfile -t saved_arr <<< "$saved"

            result=$(action_pick "saved networks" "${saved_arr[@]}")
            key=$(fzf_key "$result"); local net=$(fzf_sel "$result")
            is_back "$key" "$net" && continue

            result=$(action_pick "'$net' action" "connect" "forget")
            key=$(fzf_key "$result"); local net_action=$(fzf_sel "$result")
            is_back "$key" "$net_action" && continue

            echo ""
            case "$net_action" in
            "connect") nmcli connection up "$net" ;;
            "forget")  wifi_forget "$net" ;;
            esac
            echo ""; read -rp " Press Enter to continue..." _
            ;;
        "disconnect")
            echo ""
            wifi_disconnect
            echo ""; read -rp " Press Enter to continue..." _
            ;;
        "show status")
            echo ""
            nmcli device wifi 2>/dev/null || nmcli device status
            echo ""; read -rp " Press Enter to continue..." _
            ;;
        esac
    done
}

# ── Main loop ─────────────────────────────────────────────────────────────────

CATEGORIES=("system services" "user services" "running processes" "docker containers" "wifi" "wireguard")

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
    esac
done
