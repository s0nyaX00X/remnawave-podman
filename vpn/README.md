# Post-quantum Panel↔Node tunnel (WireGuard + Rosenpass)

Optional module: encrypt the Panel↔Node API channel at post-quantum level.
[Rosenpass](https://rosenpass.eu) runs alongside WireGuard and injects a fresh
ML-KEM-derived pre-shared key into the tunnel every ~2 minutes, so even a
harvest-now-decrypt-later quantum adversary gains nothing from recorded traffic.

Once the tunnel is up, the Panel reaches the Node over it: set the node's
address to the tunnel IP and stop exposing `NODE_PORT` publicly.

## Requirements (per server)

- WireGuard (`wg`, `ip`) and [Rosenpass](https://rosenpass.eu/docs/rosenpass-tool/guides/linux/)
- The tunnel itself is kernel networking — `sudo ./up.sh` is the one privileged
  step in this stack; everything else stays user-level

## Setup (run on BOTH servers)

```sh
cd vpn
./install.sh
```

1. Answer the prompts (role, public IPs, tunnel network, Rosenpass port).
2. Exchange public keys both ways:
   `scp -r vpn/keys/<role>.rosenpass-public user@peer:<repo>/vpn/keys/`
3. Bring the tunnel up on both servers: `sudo ./up.sh`
4. Firewall: allow UDP `9999` and `10000` (adjust to your port) from the peer IP only.

Verify: `wg show rosenpass0 preshared-keys` (both sides match, changes every ~2 min)
and `ping <tunnel-ip>`.

## Panel setup

Add the node with `address = <tunnel IP>` (e.g. `10.99.0.2`) instead of the
public IP. `NODE_PORT` no longer needs a public firewall rule — it is only
reachable through the tunnel.

Teardown: `sudo ./down.sh`
