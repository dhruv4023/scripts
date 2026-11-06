#!/usr/bin/env bash
# Simple colorful DHCP server (dnsmasq) for a /24 network.
# Usage: ./dhcp-server.sh        (asks for network only)
# Needs: dnsmasq, iproute2 (ip). NetworkManager/ufw are handled if present.

[[ $EUID -ne 0 ]] && exec sudo -E bash "$0" "$@"

# ---------- Settings (edit here) ----------
DEFAULT_NET="192.168.0.0"
POOL_START=50
POOL_END=250
LEASE_TIME="12h"
DNS="8.8.8.8"
MASK="255.255.255.0"
# ------------------------------------------

# Colors
R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; M=$'\e[35m'; C=$'\e[36m'
W=$'\e[1;37m'; D=$'\e[2m'; N=$'\e[0m'

die() { echo "${R}✖ $*${N}"; exit 1; }
command -v dnsmasq >/dev/null || die "dnsmasq not installed (sudo apt install dnsmasq)"

# ---------- Pick ethernet interface ----------
mapfile -t IFACES < <(ls /sys/class/net | while read -r i; do
    [[ -d /sys/class/net/$i/wireless || $i == lo || ! -e /sys/class/net/$i/device ]] && continue
    echo "$i"
done)
[[ ${#IFACES[@]} -eq 0 ]] && die "No ethernet interface found"

IFACE="${IFACES[0]}"
for i in "${IFACES[@]}"; do [[ $i == eno2 ]] && IFACE=eno2; done
if [[ ${#IFACES[@]} -gt 1 ]]; then
    echo "${W}Ethernet ports:${N} ${IFACES[*]}"
    read -rp "${C}Port${N} [${IFACE}]: " ans
    [[ -n $ans ]] && IFACE="$ans"
    [[ -d /sys/class/net/$IFACE ]] || die "Unknown interface $IFACE"
fi

# ---------- Ask for network (/24 only) ----------
clear
echo "${M}╔══════════════════════════════════╗${N}"
echo "${M}║${W}      Simple DHCP Server (/24)    ${M}║${N}"
echo "${M}╚══════════════════════════════════╝${N}"
echo
while true; do
    read -rp "${C}Network${N} [${DEFAULT_NET}]: " NET
    NET="${NET:-$DEFAULT_NET}"
    NET="${NET%/24}"
    if [[ $NET =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(\.0)?$ ]]; then
        a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}; c=${BASH_REMATCH[3]}
        if (( a<=255 && b<=255 && c<=255 )); then PREFIX="$a.$b.$c"; break; fi
    fi
    echo "${R}Only /24 networks allowed, e.g. 192.168.10.0${N}"
done

SERVER_IP="$PREFIX.1"
RANGE_START="$PREFIX.$POOL_START"
RANGE_END="$PREFIX.$POOL_END"

# ---------- State + cleanup ----------
TMP=$(mktemp -d)
chmod 755 "$TMP"   # dnsmasq drops privileges, its files must stay writable
: >"$TMP/leases"; : >"$TMP/log"; : >"$TMP/status"
chmod 666 "$TMP/leases" "$TMP/log"
DNSMASQ_PID=""; PROBE_PID=""; UNMANAGED=0; UFW_RULE=0

cleanup() {
    trap - EXIT INT TERM
    printf '\e[?25h'                                   # show cursor
    [[ -n $PROBE_PID ]] && kill "$PROBE_PID" 2>/dev/null
    [[ -n $DNSMASQ_PID ]] && kill "$DNSMASQ_PID" 2>/dev/null
    ip addr del "$SERVER_IP/24" dev "$IFACE" 2>/dev/null
    [[ $UNMANAGED -eq 1 ]] && nmcli dev set "$IFACE" managed yes >/dev/null 2>&1
    [[ $UFW_RULE -eq 1 ]] && ufw delete allow in on "$IFACE" to any port 67 proto udp >/dev/null 2>&1
    rm -rf "$TMP"
    echo; echo "${G}DHCP server stopped, port restored.${N}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------- Configure port: manual static IP ----------
# NetworkManager drops a port's IP when the cable goes up/down, which breaks
# DHCP. So we mark the port unmanaged while running and set the IP ourselves.
echo; echo "${D}Setting $IFACE → $SERVER_IP/24 gw $SERVER_IP (manual) ...${N}"
if command -v nmcli >/dev/null && systemctl is-active -q NetworkManager 2>/dev/null; then
    nmcli con delete "dhcp-server-$IFACE" &>/dev/null   # leftover from older version
    nmcli dev set "$IFACE" managed no >/dev/null 2>&1 && UNMANAGED=1
fi
ip addr flush dev "$IFACE"
ip addr add "$SERVER_IP/24" dev "$IFACE" || die "could not set IP on $IFACE"
ip link set "$IFACE" up

# Let DHCP through ufw if it is active
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active" \
   && ! ufw status 2>/dev/null | grep -q "67/udp on $IFACE"; then
    ufw allow in on "$IFACE" to any port 67 proto udp >/dev/null 2>&1 && UFW_RULE=1
fi

# ---------- Start dnsmasq ----------
dnsmasq --no-daemon --port=0 --interface="$IFACE" --bind-dynamic \
    --dhcp-authoritative --dhcp-broadcast \
    --dhcp-range="$RANGE_START,$RANGE_END,$MASK,$LEASE_TIME" \
    --dhcp-option=option:router,"$SERVER_IP" \
    --dhcp-option=option:dns-server,"$DNS" \
    --dhcp-leasefile="$TMP/leases" \
    --log-facility="$TMP/log" \
    --pid-file="" >"$TMP/stdout" 2>&1 &
DNSMASQ_PID=$!
sleep 1
kill -0 "$DNSMASQ_PID" 2>/dev/null || die "dnsmasq failed: $(cat "$TMP/stdout")"

# ---------- Online/offline probe (background) ----------
# Pings each leased device; the ARP result tells us if it is really there,
# even when the device blocks ping.
probe() {
    while true; do
        if [[ -s $TMP/leases ]]; then
            : >"$TMP/status.new"
            while read -r _ _ ip _; do
                (
                    ping -c1 -W1 "$ip" >/dev/null 2>&1
                    st=$(ip neigh show "$ip" dev "$IFACE" | awk '{print $NF}')
                    case $st in REACHABLE|STALE|DELAY|PROBE) s=online ;; *) s=offline ;; esac
                    echo "$ip $s" >>"$TMP/status.new"
                ) </dev/null &
            done <"$TMP/leases"
            wait
            mv -f "$TMP/status.new" "$TMP/status"
        fi
        sleep 3
    done
}
probe &
PROBE_PID=$!

# ---------- Dashboard ----------
render() {
    local now carrier lk
    now=$(date +%s)
    carrier=$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0)
    # self-heal: keep the server IP on the port
    ip -4 addr show dev "$IFACE" | grep -q "inet $SERVER_IP/" \
        || ip addr add "$SERVER_IP/24" dev "$IFACE" 2>/dev/null
    if [[ $carrier == 1 ]]; then lk="${G}● cable connected${N}"
    else lk="${R}○ no cable / link down${N}"; fi

    printf '\e[H'
    {
    echo "${M}╔══════════════════════════════════════════════════════════════════════╗${N}"
    echo "${M}║${W}  DHCP SERVER  ${G}● running${N}                                                ${M}║${N}"
    echo "${M}╚══════════════════════════════════════════════════════════════════════╝${N}"
    echo " ${C}Port${N}    $IFACE  $lk   ${C}Server/Gateway${N}  $SERVER_IP"
    echo " ${C}Network${N} $PREFIX.0/24   ${C}DNS${N} $DNS   ${C}Lease${N} $LEASE_TIME"
    echo " ${C}Pool${N}    $RANGE_START - $RANGE_END"
    echo
    local count; count=$(wc -l < "$TMP/leases")
    echo " ${W}DEVICES${N} ${D}($count leased)${N}"
    printf " ${Y}%-15s %-17s %-16s %-11s %s${N}\n" "IP ADDRESS" "MAC ADDRESS" "NAME" "STATUS" "LEASE LEFT"
    echo " ${D}──────────────────────────────────────────────────────────────────────${N}"
    if [[ $count -eq 0 ]]; then
        echo " ${D}Waiting for devices to connect...${N}"
    else
        sort -k3,3V "$TMP/leases" | awk -v now="$now" -v up="$carrier" \
            -v g="$G" -v r="$R" -v y="$Y" -v n="$N" '
            FILENAME==ARGV[1] { st[$1]=$2; next }
            {
                left=$1-now
                if ($1==0) t="infinite"; else if (left<=0) t="expired";
                else t=sprintf("%dh %02dm", left/3600, (left%3600)/60)
                name=($4=="*"||$4=="")?"-":$4
                s=st[$3]; if (up!=1) s="offline"
                if (s=="online")                    { col=g; sym="●"; lab="online" }
                else if (s=="offline"||t=="expired") { col=r; sym="○"; lab="offline" }
                else                                 { col=y; sym="…"; lab="checking" }
                printf " %s%-15s%s %-17s %-16s %s%s %-9s%s %s\n", col, $3, n, $2, substr(name,1,15), col, sym, lab, n, t
            }' "$TMP/status" -
    fi
    echo
    echo " ${W}RECENT ACTIVITY${N}"
    echo " ${D}──────────────────────────────────────────────────────────────────────${N}"
    grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK|NAK|RELEASE|INFORM)' "$TMP/log" | tail -8 | awk \
        -v g="$G" -v y="$Y" -v c="$C" -v r="$R" -v b="$B" -v n="$N" -v d="$D" '{
        t=$3; k=0;
        for(i=1;i<=NF;i++) if($i ~ /^DHCP[A-Z]+\(/){k=i;break}
        if(!k) next;
        ev=$k; sub(/\(.*/,"",ev); sub(/^DHCP/,"",ev);
        ip="";mac="";host="";
        for(i=k+1;i<=NF;i++){ if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) ip=$i;
            else if(length($i)==17 && $i ~ /^[0-9a-fA-F:]+$/) mac=$i; else host=$i }
        col=c; msg="is looking for a server";
        if(ev=="OFFER"){col=b;msg="offered " ip}
        else if(ev=="REQUEST"){col=y;msg="requested " (ip?ip:"an address")}
        else if(ev=="ACK"){col=g;msg="got " ip (host?" ("host")":"")}
        else if(ev=="NAK"){col=r;msg="request refused"}
        else if(ev=="RELEASE"){col=r;msg="released " ip}
        else if(ev=="INFORM"){msg="asked for config"}
        printf " %s%s%s  %s%-8s%s %s  %s\n", d,t,n,col,ev,n,mac,msg }'
    echo
    echo " ${D}Press ${W}q${D} to stop the server and restore the port${N}"
    } | sed $'s/$/\e[K/'
    printf '\e[J'
}

printf '\e[?25l'; clear
while kill -0 "$DNSMASQ_PID" 2>/dev/null; do
    render
    read -rsn1 -t 1 key && [[ $key == q || $key == Q ]] && break
done
