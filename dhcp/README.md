# DHCP Debug Server

This script starts a DHCP debug server using `dnsmasq` and captures network traffic in real-time for troubleshooting DHCP operations.

## Overview

`start-dhcp-server.sh` is a debugging tool that:
- Launches a DHCP server using dnsmasq with detailed logging
- Simultaneously captures and displays DHCP network packets using tcpdump
- Displays server configuration in a formatted interface
- Automatically cleans up resources on exit

## Prerequisites

- Linux system with `sudo` access
- `dnsmasq` package installed
  ```bash
  sudo apt-get install dnsmasq
  ```
- `tcpdump` package installed
  ```bash
  sudo apt-get install tcpdump
  ```

## Configuration

Edit the variables at the top of the script to customize:

```bash
IFACE="eno2"                    # Network interface to bind to
SERVER_IP="192.168.102.1"       # DHCP server IP address
RANGE_START="192.168.102.100"   # DHCP pool start address
RANGE_END="192.168.102.200"     # DHCP pool end address
```

## Usage

```bash
./start-dhcp-server.sh
```

The script requires `sudo` privileges to run. It will:
1. Display the server configuration
2. Start dnsmasq with DHCP and debug logging (left side)
3. Start tcpdump on DHCP ports (right side)
4. Stream real-time logs from both services

## Output

The script displays two parallel logs:
- **[DNSMASQ]**: DHCP server activity with lease assignments and debug information
- **[TCPDUMP]**: Raw network packets exchanged on DHCP ports (67/68)

Example output:
```
╔══════════════════════════════════════════════════════════════╗
║                    DHCP DEBUG SERVER                       ║
╠══════════════════════════════════════════════════════════════╣
║  Interface : eno2                                           ║
║  Server IP : 192.168.102.1                                  ║
║  DHCP Pool : 192.168.102.100 - 192.168.102.200             ║
╠══════════════════════════════════════════════════════════════╣
║  DNSMASQ → left       TCPDUMP → right                    ║
╚══════════════════════════════════════════════════════════════╝
```

## Stopping the Server

Press `Ctrl+C` or send a signal (`INT`, `TERM`) to stop. The script will:
- Terminate the dnsmasq process
- Terminate the tcpdump process
- Display cleanup message

## Exit Handling

The script uses signal traps to ensure clean shutdown:
- `trap cleanup EXIT INT TERM` catches termination signals
- Safely kills both `dnsmasq` and `tcpdump` processes
- Suppresses error messages if processes already terminated

## DHCP Configuration Details

- **Subnet Mask**: 255.255.255.0
- **Lease Duration**: 12 hours
- **DHCP Ports**: 
  - Port 67: Server (bootps)
  - Port 68: Client (bootpc)

## Troubleshooting

**Port already in use:**
- Ensure no other DHCP server is running on the interface
- Check: `sudo lsof -i :67`

**Permission denied:**
- Script requires `sudo` for both dnsmasq and tcpdump
- Run with: `sudo ./start-dhcp-server.sh`

**Interface not found:**
- Verify the interface exists: `ip link show`
- Update `IFACE` variable in the script

**dnsmasq fails to start:**
- Check if dnsmasq is already running: `ps aux | grep dnsmasq`
- Verify dnsmasq is installed: `which dnsmasq`
