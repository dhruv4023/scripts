# LAN Share

Share the files in the current directory with devices on a local network using a temporary HTTP server.

The script asks you to choose an active IPv4 interface, shows the selected address and subnet, and asks for confirmation before sharing. It opens TCP port `8000` in UFW only for that interface and subnet, then removes the rule when the server exits.

## Requirements

- Linux with Bash
- `ip`, `sudo`, `ufw`, `awk`, and BusyBox with its `httpd` applet (script offers to install BusyBox if missing)
- UFW enabled and active

## Usage

Run the script from the directory you want to share:

```bash
cd /path/to/folder
/path/to/lan-share/lan-share.sh
```

Choose the interface/address connected to the receiving devices and confirm the sharing prompt. On another device on that subnet, open the displayed URL, for example:

```text
http://192.168.1.20:8000
```

The server exposes the directory from which the script was launched. Use the web page to browse and download files. Press **Ctrl+C** to stop the server; the temporary UFW rule is removed on exit.

## Safety notes

- Anyone able to connect from the selected subnet can access and download files in the shared directory. Check the directory contents before confirming.
- This is an unauthenticated, read-only HTTP share. Do not use it on an untrusted network or to share sensitive files.
- The script uses port `8000` and exits if an existing UFW rule already mentions that port. Review the existing rule before trying again.
- Keep the script running while devices are downloading; stopping it ends access.
