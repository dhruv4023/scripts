# scripts

A small collection of useful Linux shell scripts for configuring two-device Ethernet networking and other automation tasks.

## Table of Contents

- [two-device-ip-config-ethernet](./two-device-ip-config-ethernet/README.md)

## Projects

### two-device-ip-config-ethernet
A pair of scripts to configure a host laptop and a remote device on a dedicated Ethernet network. The host forwards traffic from the remote device to the internet via a separate wireless interface.

- `two-device-ip-config-ethernet/host.sh` — configure the host machine with a static Ethernet IP, enable IPv4 forwarding, and apply NAT/forwarding rules.
- `two-device-ip-config-ethernet/remote.sh` — configure the remote machine with a static Ethernet IP, set the host as the default gateway, and verify connectivity.

## Usage

1. Review and adjust interface names in each script (`ETH`, `wlo1`, etc.).
2. Run the scripts with sudo on the respective machines.
3. Confirm connectivity and DNS once configuration is complete.

## Notes

- These scripts are designed for Debian/Ubuntu-style systems using `ip`, `iptables`, and `resolvectl`.
- Modify IP addresses and interface names to fit your network before running.
