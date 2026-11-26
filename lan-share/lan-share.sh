#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_PORT=8000
PORT="${1:-$DEFAULT_PORT}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [PORT]

Share the current directory over HTTP to devices on your local subnet.
  PORT  TCP port to listen on (default: $DEFAULT_PORT)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
    echo "Error: Invalid port '$PORT'. Must be an integer between 1 and 65535." >&2
    exit 1
fi

# Colors when running in an interactive terminal
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    CYAN=$'\033[36m'
    RESET=$'\033[0m'
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" RESET=""
fi

info()  { printf "%s[INFO]%s %s\n" "$CYAN" "$RESET" "$*"; }
ok()    { printf "%s[OK]%s   %s\n" "$GREEN" "$RESET" "$*"; }
warn()  { printf "%s[WARN]%s %s\n" "$YELLOW" "$RESET" "$*"; }
err()   { printf "%s[ERR]%s  %s\n" "$RED" "$RESET" "$*" >&2; }

# Check dependencies
for cmd in ip sudo ufw awk grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Required command '$cmd' is not installed."
        exit 1
    fi
done

install_busybox() {
    local pkg_mgr=""
    local install_cmd=""

    if command -v apt-get >/dev/null 2>&1; then
        pkg_mgr="apt-get"
        install_cmd="sudo apt-get update && sudo apt-get install -y busybox"
    elif command -v dnf >/dev/null 2>&1; then
        pkg_mgr="dnf"
        install_cmd="sudo dnf install -y busybox"
    elif command -v yum >/dev/null 2>&1; then
        pkg_mgr="yum"
        install_cmd="sudo yum install -y busybox"
    elif command -v pacman >/dev/null 2>&1; then
        pkg_mgr="pacman"
        install_cmd="sudo pacman -S --noconfirm busybox"
    elif command -v zypper >/dev/null 2>&1; then
        pkg_mgr="zypper"
        install_cmd="sudo zypper install -y busybox"
    elif command -v apk >/dev/null 2>&1; then
        pkg_mgr="apk"
        install_cmd="sudo apk add busybox"
    else
        err "BusyBox is not installed and no supported package manager was found."
        exit 1
    fi

    warn "BusyBox is not installed."
    printf "  Install command: %s%s%s\n" "$DIM" "$install_cmd" "$RESET"
    read -rp "Install BusyBox now using $pkg_mgr? [y/N] " install_confirm
    if [[ ! "$install_confirm" =~ ^[Yy]$ ]]; then
        err "BusyBox is required to run this script."
        exit 1
    fi

    bash -c "$install_cmd"
}

if ! command -v busybox >/dev/null 2>&1; then
    install_busybox
fi

if ! busybox --list | grep -qx httpd; then
    err "BusyBox 'httpd' applet is unavailable."
    exit 1
fi

# Discover active global IPv4 interface addresses
mapfile -t ADDRESSES < <(
    ip -o -4 addr show up scope global |
    awk '{print $2, $4}'
)

if ((${#ADDRESSES[@]} == 0)); then
    err "No active network interface with a global IPv4 address was found."
    exit 1
fi

echo
printf "%s=== LAN Share ===%s\n" "$BOLD" "$RESET"

if ((${#ADDRESSES[@]} == 1)); then
    read -r INTERFACE CIDR <<< "${ADDRESSES[0]}"
    info "Only one active IPv4 interface found; automatically selected: ${BOLD}${INTERFACE} (${CIDR})${RESET}"
else
    echo
    echo "Available network interfaces:"
    echo
    for i in "${!ADDRESSES[@]}"; do
        read -r iface cidr <<< "${ADDRESSES[$i]}"
        printf "  %s%d)%s %-12s %s\n" "$BOLD" "$((i + 1))" "$RESET" "$iface" "$cidr"
    done
    echo

    while true; do
        read -rp "Select interface [1-${#ADDRESSES[@]}] (or 'q' to quit): " selection
        if [[ "$selection" =~ ^[Qq]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        if [[ "$selection" =~ ^[0-9]+$ ]] && ((selection >= 1 && selection <= ${#ADDRESSES[@]})); then
            read -r INTERFACE CIDR <<< "${ADDRESSES[$((selection - 1))]}"
            break
        fi
        warn "Invalid selection. Enter a number from 1 to ${#ADDRESSES[@]}, or 'q' to quit."
    done
fi

IP=${CIDR%/*}
PREFIX=${CIDR#*/}

if [[ ! "$PREFIX" =~ ^[0-9]+$ ]] || ((PREFIX < 0 || PREFIX > 32)); then
    err "Unexpected CIDR prefix '$PREFIX' on interface $INTERFACE."
    exit 1
fi

# Convert IPv4 address to 32-bit integer
ip_to_int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo "$(( (a << 24) | (b << 16) | (c << 8) | d ))"
}

# Convert 32-bit integer back to IPv4 address
int_to_ip() {
    local value=$1
    printf '%d.%d.%d.%d' \
        "$(( (value >> 24) & 255 ))" \
        "$(( (value >> 16) & 255 ))" \
        "$(( (value >> 8) & 255 ))" \
        "$(( value & 255 ))"
}

# Calculate subnet from interface IP and prefix
IP_INT=$(ip_to_int "$IP")
if ((PREFIX == 0)); then
    MASK=0
else
    MASK=$(( (0xFFFFFFFF << (32 - PREFIX)) & 0xFFFFFFFF ))
fi
NETWORK=$(( IP_INT & MASK ))
NETWORK_IP=$(int_to_ip "$NETWORK")
SUBNET="${NETWORK_IP}/${PREFIX}"

# Inspect UFW firewall state
echo
info "Checking UFW firewall status (may prompt for sudo password)..."
sudo -v

UFW_STATUS_OUT=$(sudo ufw status)
UFW_ACTIVE=0
FIREWALL_ACTION="none"   # none | add | conflict
RULE_ADDED=0

UFW_RULE_ARGS=(
    allow in on "$INTERFACE"
    from "$SUBNET"
    to "$IP" port "$PORT" proto tcp
)
UFW_RULE_CMD="sudo ufw ${UFW_RULE_ARGS[*]}"

if ! grep -q '^Status: active' <<< "$UFW_STATUS_OUT"; then
    FIREWALL_ACTION="inactive"
else
    UFW_ACTIVE=1
    UFW_ADDED_OUT=$(sudo ufw show added 2>/dev/null || true)
    EXACT_RULE_LINE="ufw allow in on ${INTERFACE} from ${SUBNET} to ${IP} port ${PORT} proto tcp"

    if grep -Fqx "$EXACT_RULE_LINE" <<< "$UFW_ADDED_OUT"; then
        FIREWALL_ACTION="exists"
    elif grep -qE "(^|[^0-9])${PORT}([^0-9]|$)" <<< "$UFW_STATUS_OUT"; then
        FIREWALL_ACTION="conflict"
        EXISTING_PORT_RULES=$(grep -E "(^|[^0-9])${PORT}([^0-9]|$)" <<< "$UFW_STATUS_OUT" || true)
    else
        FIREWALL_ACTION="add"
    fi
fi

# Present full sharing and firewall summary to the user
echo
printf "%sSharing Configuration:%s\n" "$BOLD" "$RESET"
printf "  Directory : %s\n" "$PWD"
printf "  Interface : %s\n" "$INTERFACE"
printf "  IP Address: %s\n" "$IP"
printf "  Netmask   : /%s\n" "$PREFIX"
printf "  Subnet    : %s\n" "$SUBNET"
printf "  Port      : %s/tcp\n" "$PORT"
printf "  Share URL : %shttp://%s:%s%s\n" "$BOLD" "$IP" "$PORT" "$RESET"
echo

printf "%sFirewall Plan (UFW):%s\n" "$BOLD" "$RESET"
case "$FIREWALL_ACTION" in
    add)
        printf "  Status    : Active (no existing rule for port %s)\n" "$PORT"
        printf "  Action    : %sAdd temporary ALLOW rule%s\n" "$YELLOW" "$RESET"
        printf "  Rule      : Allow TCP port %s IN on %s from %s to %s\n" "$PORT" "$INTERFACE" "$SUBNET" "$IP"
        printf "  Command   : %s%s%s\n" "$DIM" "$UFW_RULE_CMD" "$RESET"
        printf "  On Exit   : This temporary rule will be automatically deleted.\n"
        ;;
    exists)
        printf "  Status    : Active\n"
        printf "  Action    : %sNo changes needed%s (matching UFW rule already exists)\n" "$GREEN" "$RESET"
        printf "  Rule      : %s\n" "$EXACT_RULE_LINE"
        printf "  On Exit   : Existing rule will be left untouched.\n"
        ;;
    conflict)
        printf "  Status    : Active\n"
        printf "  Action    : %sNo changes will be made automatically%s\n" "$YELLOW" "$RESET"
        printf "  Reason    : Existing UFW rule(s) already reference port %s:\n" "$PORT"
        while IFS= read -r line; do
            printf "              %s\n" "$line"
        done <<< "$EXISTING_PORT_RULES"
        printf "  Hint      : Inspect with 'sudo ufw status numbered' if needed.\n"
        ;;
    inactive)
        printf "  Status    : %sInactive%s\n" "$YELLOW" "$RESET"
        printf "  Action    : No firewall rules will be added or removed.\n"
        ;;
esac

echo
warn "Anyone on subnet ${SUBNET} can browse and download files from '${PWD}' (unauthenticated HTTP)."
echo

case "$FIREWALL_ACTION" in
    add)
        read -rp "Apply this temporary firewall rule and start sharing? [y/N] " confirm
        ;;
    conflict)
        read -rp "Start sharing WITHOUT modifying the existing firewall rules? [y/N] " confirm
        ;;
    inactive)
        read -rp "UFW is inactive. Start sharing without firewall rules? [y/N] " confirm
        ;;
    exists)
        read -rp "Start sharing using the existing firewall rule? [y/N] " confirm
        ;;
esac

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled. No changes were made."
    exit 0
fi

TEMP_INDEX_FILE=""

html_escape() {
    local s=$1
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    s=${s//\'/&#39;}
    printf '%s' "$s"
}

url_encode() {
    local LC_ALL=C
    local s=$1 i ch
    for ((i = 0; i < ${#s}; i++)); do
        ch=${s:i:1}
        case "$ch" in
            [a-zA-Z0-9.~_-]) printf '%s' "$ch" ;;
            *) printf '%%%02X' "'$ch" ;;
        esac
    done
}

create_temp_index() {
    local index_path="$PWD/index.html"
    [[ -e "$index_path" ]] && return 0

    TEMP_INDEX_FILE="$index_path"
    {
        printf '<!DOCTYPE html>\n<html><head><meta charset="utf-8">'
        printf '<title>Index of %s</title>' "$(html_escape "$PWD")"
        printf '<style>body{font-family:system-ui,sans-serif;max-width:860px;margin:2rem auto;padding:0 1rem}'
        printf 'table{width:100%%;border-collapse:collapse}th,td{text-align:left;padding:.45rem .6rem;border-bottom:1px solid #ddd}'
        printf 'a{text-decoration:none;color:#0969da}a:hover{text-decoration:underline}</style></head><body>\n'
        printf '<h2>Files in %s</h2>\n<table><thead><tr><th>Name</th><th>Size</th></tr></thead><tbody>\n' "$(html_escape "$PWD")"

        local entry name href label size
        shopt -s nullglob dotglob
        for entry in "$PWD"/*; do
            name=${entry##*/}
            [[ "$name" == "index.html" ]] && continue
            href=$(url_encode "$name")
            label=$(html_escape "$name")
            if [[ -d "$entry" ]]; then
                printf '<tr><td><a href="%s/">%s/</a></td><td>-</td></tr>\n' "$href" "$label"
            else
                size=$(wc -c < "$entry" 2>/dev/null || echo "-")
                printf '<tr><td><a href="%s">%s</a></td><td>%s B</td></tr>\n' "$href" "$label" "$size"
            fi
        done
        shopt -u nullglob dotglob

        printf '</tbody></table></body></html>\n'
    } > "$TEMP_INDEX_FILE"
}

cleanup() {
    if [[ -n "$TEMP_INDEX_FILE" && -f "$TEMP_INDEX_FILE" ]]; then
        rm -f -- "$TEMP_INDEX_FILE"
        TEMP_INDEX_FILE=""
    fi
    if ((RULE_ADDED == 1)); then
        echo
        info "Removing temporary UFW firewall rule..."
        if sudo ufw --force delete "${UFW_RULE_ARGS[@]}" >/dev/null; then
            ok "Temporary firewall rule removed."
        else
            warn "Could not remove temporary firewall rule automatically. Check 'sudo ufw status numbered'."
        fi
        RULE_ADDED=0
    fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$FIREWALL_ACTION" == "add" ]]; then
    echo
    info "Adding temporary UFW rule: $UFW_RULE_CMD"
    sudo ufw "${UFW_RULE_ARGS[@]}"
    RULE_ADDED=1
    ok "Temporary firewall rule added."
fi

create_temp_index
if [[ -n "$TEMP_INDEX_FILE" ]]; then
    info "Generated temporary index.html for directory browsing (will be removed on exit)."
fi

echo
printf "%sStarting BusyBox HTTP server...%s\n" "$BOLD" "$RESET"
printf "  Share URL   : %shttp://%s:%s%s\n" "$GREEN" "$IP" "$PORT" "$RESET"
printf "  Allowed LAN : %s\n" "$SUBNET"
printf "  Directory   : %s\n" "$PWD"
echo
echo "Press Ctrl+C to stop sharing."
echo

busybox httpd -f -v -p "${IP}:${PORT}" -h "$PWD"
