# two-device-ip-config-ethernet

This folder contains two shell scripts that set up a direct Ethernet connection between a host machine and a remote device.

The host machine shares its internet connection over Ethernet, and the remote device routes traffic through the host.

## Files

- `host.sh`
  - Sets the host Ethernet interface to `192.168.0.10/24`
  - Enables IPv4 forwarding
  - Adds NAT rules from the Ethernet interface to the host wireless internet interface (`wlo1`)
  - Allows forwarding for established connections

- `remote.sh`
  - Sets the remote Ethernet interface to `192.168.0.11/24`
  - Configures the host (`192.168.0.10`) as the default gateway
  - Sets DNS servers with `resolvectl`
  - Performs basic connectivity tests to the host, internet, and DNS resolution

## Usage

1. Open each script and verify interface names and IP addresses for your system.
   - `host.sh` uses `ETH="eno2"` and forwards via `wlo1`
   - `remote.sh` uses `ETH="eno1"`
2. Make the scripts executable if needed:

   ```bash
   chmod +x host.sh remote.sh
   ```

3. Run `host.sh` on the host machine:

   ```bash
   sudo ./host.sh
   ```

4. Run `remote.sh` on the remote machine:

   ```bash
   sudo ./remote.sh
   ```

## Customization

- Change `HOST_IP`, `REMOTE_IP`, and `GATEWAY` values to match your desired network.
- Update interface names if your Ethernet interfaces are not `eno1` / `eno2`.
- If your host internet interface is not `wlo1`, change the `iptables` NAT rules in `host.sh` accordingly.

## Important

- Both scripts require root privileges.
- Be careful when flushing IP addresses and modifying routes on active systems.
- These scripts are intended for lab or test network setups, not production network infrastructure.
