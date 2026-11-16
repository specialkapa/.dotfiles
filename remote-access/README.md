# remote access (iPhone → Omarchy over Tailscale)

SSH and Remote Desktop (RDP) into the Omarchy laptop from my iPhone, from anywhere, without
exposing anything to the internet or the LAN. `../setup.sh` offers to run this on the Omarchy
profile; to run it on its own (from a terminal inside the desktop):

```bash
~/.dotfiles/remote-access/setup.sh               # idempotent; asks for sudo
~/.dotfiles/remote-access/setup.sh --reconfigure # also redo the RDP settings/password
```

## What it sets up

| piece | where | from |
| --- | --- | --- |
| Tailscale | `tailscaled` (enabled at boot), logged in | `tailscale up` if needed |
| Firewall guard | `/etc/nftables.d/tailnet-guard.nft` + `tailnet-guard.service` | generated from [`peers.conf`](./peers.conf) |
| ufw rules | allowed peers only on ports 22/3389; "SSH from anywhere" rules removed | `peers.conf` |
| SSH | `/etc/ssh/sshd_config.d/10-hardening.conf` (keys only, no root, `AllowUsers` me) | [`sshd-hardening.conf`](./sshd-hardening.conf) |
| iPhone SSH key | appended to `~/.ssh/authorized_keys` | [`authorized_keys`](./authorized_keys) (public key) |
| Remote Desktop | `kokd.remote-desktop` plugin + `hypr-rdp` (AUR), bound to this machine's Tailscale IP, sharing `RDP_OUTPUT`, on at every desktop login | `peers.conf` |

**Why an nftables guard and not just ufw:** Tailscale inserts its own `ts-input` chain at the top
of `INPUT` with `-i tailscale0 -j ACCEPT`, so ufw never sees tailnet traffic. The guard is a
separate `inet tailnet_guard` table hooked at priority -10 (before iptables/ufw/Tailscale); it
drops ports 22 and 3389 unless the packet comes from loopback or an allowed peer over
`tailscale0`. It survives ufw/Tailscale/Docker reloads because nobody else touches that table.
The ufw rules mirror it so `ufw status` tells the truth.

## Secrets (never in this repo — it is public)

- RDP password: typed in when the script asks, or generated and written to
  `~/rdp-iphone-password.txt` (mode 600). Keep it in a password manager and delete the file.
- The plugin stores the password, its TLS key/cert and settings in
  `~/.config/omarchy-remote-desktop/` (mode 700). A new machine gets a new certificate, so the
  iPhone will show a new fingerprint: compare it with the one the script prints.
- The SSH **private** key lives on the iPhone; only its public key is here.

## Day to day

- Remote Desktop is on whenever I'm logged into the desktop; turn it off/on from the bar panel or
  `python3 ~/.config/omarchy/plugins/kokd.remote-desktop/bin/remote-desktopctl disable|enable`.
  Nothing is reachable while the laptop sleeps or is logged out.
- iPhone apps: Tailscale (connected) + Microsoft **Windows App** (Add PC → Tailscale IP, user
  `rdp-iphone`) and any SSH client with the key above.
- New device allowed? Add its Tailscale IPs to `peers.conf` and re-run the script.
- Remove the guard: `sudo systemctl disable --now tailnet-guard`.

## Optional: Tailscale ACL (extra layer, set in the admin console)

<https://login.tailscale.com/admin/acls> — enforced by Tailscale itself before traffic reaches the
laptop. Replaces the default allow-all, so any device added later gets nothing until allowed.
`omarchy` is this machine's Tailscale IP (check `tailscale ip -4`; it changes on a new machine).

```json
{
  "hosts": { "omarchy": "100.117.231.68", "iphone": "100.101.241.116" },
  "acls": [
    { "action": "accept", "src": ["iphone"],  "dst": ["omarchy:22,3389"] },
    { "action": "accept", "src": ["omarchy"], "dst": ["iphone:*"] }
  ]
}
```
