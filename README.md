# Crocs Men MC Server — Operations Manual

A Minecraft **26.2** server running **Fabric** via Docker Compose, using the
`itzg/minecraft-server:java25` image. This file documents the current live
configuration, what every setting does, and how to perform common admin
tasks. Treat this as the source of truth over memory — if it disagrees with
`.env` or `compose.yaml`, those files win (and this doc is out of date).

- **Domain:** `crocsmc.my.id`
- **Port:** `25565` (TCP, Java Edition only — no Bedrock/Geyser support)
- **Containers:** `mc` (the game server) and `mc-backup` (periodic world backups)

## File layout

| Path | Purpose |
|---|---|
| `compose.yaml` | Docker Compose service definitions for `mc` and `mc-backup`. Safe to commit. |
| `.env` | Your actual secrets/settings. Mode `600`, gitignored, **never commit this**. |
| `.env.example` | Placeholder template showing the schema. Safe to commit. |
| `check.sh` | Quick health check: DNS resolution, port reachability, container status. |
| `data/` | The live world, `server.properties`, `ops.json`, mods, configs. Gitignored. |
| `backups/` | Periodic world archives written by `mc-backup`. Gitignored. |

## Current configuration (`.env`)

| Variable | Current value | What it controls |
|---|---|---|
| `SERVER_DOMAIN` | `crocsmc.my.id` | Public hostname players connect to; also baked into the MOTD. |
| `MC_VERSION` | `26.2` | Minecraft version. Changing this on an existing world needs a backup first — see the original setup doc. |
| `MC_MEMORY` | `4G` | JVM heap size. **Lowered from the schema's 6G default** — this host has ~7.4GB usable RAM (not a full 8GB), and 6G left only ~600MB free with swap active. 4G leaves ~2.2GB headroom. Don't raise this without checking `free -h` afterward. |
| `TZ` | `Asia/Jakarta` | Container timezone, used for log timestamps and backup scheduling. |
| `MC_MOTD` | `Crocs Men MC Server 🏳️‍🌈` | Server list message (domain is appended automatically). |
| `MAX_PLAYERS` | `10` | Concurrent player cap. |
| `DIFFICULTY` | `normal` | Game difficulty. |
| `VIEW_DISTANCE` | `14` | **Above the 4–12 range** the original setup doc recommended for this host's specs. Higher view distance = more chunk-loading memory/CPU load; keep an eye on `docker stats` if lag shows up, and consider dropping it back toward 10–12. |
| `SIMULATION_DISTANCE` | `8` | How far entity/redstone simulation extends. |
| `ONLINE_MODE` | `FALSE` | **Offline mode** — see Security posture below. |
| `WHITELIST` | *(commented out)* | Was `playername1,playername2` placeholders, never real names. Whitelist is fully disabled right now — see below. |
| `OPS` | *(commented out)* | Startup-time op provisioning only works for **online-mode** Mojang lookups. In offline mode, ops are managed live via RCON instead (see Admin tasks). |
| `RCON_PASSWORD` | *(unset, image default)* | Intentionally passwordless for now — safe only because port 25575 is never published in `compose.yaml`. Set a real value here later to secure it, then `docker compose up -d`. |
| `MODRINTH_PROJECTS` | `fabric-api,easyauth` | Mods auto-installed from Modrinth. EasyAuth was added to support offline mode (see below). |
| `INSTALL_COBBLEMON` | `false` | Not installed. |
| `BACKUP_INTERVAL` | `6h` | How often `mc-backup` snapshots the world. |
| `PRUNE_BACKUPS_DAYS` | `7` | Backups older than this are deleted. |

## Security posture / known risks

- **Offline mode is on (`ONLINE_MODE=FALSE`).** The server no longer verifies
  players against Mojang — anyone can *claim* any username. **EasyAuth** is
  installed specifically to cover this gap: every player must run
  `/register <password> <password>` on their first join and `/login
  <password>` on every join after that. Without EasyAuth, offline mode would
  let anyone impersonate anyone by username alone.
- **Whitelist is disabled.** `ENABLE_WHITELIST`/`ENFORCE_WHITELIST` are set to
  `FALSE` in `compose.yaml`, and `WHITELIST` is emptied in `.env` (the image
  force-enables the whitelist whenever `WHITELIST` is non-empty, regardless of
  those flags — both had to change together). The server is open to anyone
  who can reach port 25565 and knows/guesses a password via EasyAuth.
- **RCON is passwordless by design**, acceptable only because `compose.yaml`
  publishes just `25565:25565` — port 25575 is never exposed to the host or
  internet. Confirmed via `ss -tlnp | grep 25575` (nothing listens there).
  Deferred: set `RCON_PASSWORD` in `.env` later to secure it further.
- **SSH hardening is incomplete.** `PermitRootLogin` and `PasswordAuthentication`
  are still at their defaults (`yes`) because `~/.ssh/authorized_keys` was
  empty when this step came up during setup. To finish it: add your public
  key to `~/.ssh/authorized_keys`, confirm it's non-empty, then apply
  `PasswordAuthentication no` / `PermitRootLogin no` via
  `/etc/ssh/sshd_config.d/99-hardening.conf` and `systemctl restart ssh` —
  **only after** confirming key-based login works, to avoid lockout.
- **`ops.json` currently lists exactly one op: `Naggars`.** This was added
  live via `rcon-cli op Naggars` (not through `.env`'s `OPS=`, since that
  path only resolves usernames through Mojang and fails in offline mode). A
  leftover placeholder op (`playername1`, from an earlier online-mode boot)
  was found and removed — in offline mode, any leftover op name is a
  standing privilege-escalation risk, since anyone can connect as that name.

## Common admin tasks

```bash
cd ~/mc

# View recent logs
docker compose logs --tail=200 mc

# Apply a change made in .env or compose.yaml (NOT docker compose restart —
# that does not re-read .env)
docker compose up -d

# Add/remove an operator (works live, no restart, works in offline mode)
docker exec -i mc rcon-cli op <username>
docker exec -i mc rcon-cli deop <username>

# List online players / whitelist contents
docker exec -i mc rcon-cli list
docker exec -i mc rcon-cli whitelist list

# Re-enable the whitelist:
#   1. In .env: uncomment WHITELIST= and fill in real usernames
#   2. In compose.yaml: set ENABLE_WHITELIST and ENFORCE_WHITELIST back to "TRUE"
#   3. docker compose up -d

# Check memory headroom (keep at least ~1.5GB available)
docker stats --no-stream mc
free -h

# Run the health check (DNS + port + container status)
./check.sh
```

## Backups

`mc-backup` runs alongside `mc`, writing archives to `~/mc/backups` every
`BACKUP_INTERVAL` (currently 6h), pruning anything older than
`PRUNE_BACKUPS_DAYS` (currently 7 days). Off-site sync (e.g. via `rclone` to
Backblaze B2 / Cloudflare R2 / Google Drive) has **not** been set up yet —
that's a manual step per the original setup doc (Phase 6), since it requires
you to run `rclone config` yourself with your own credentials. A restore
test (extract the newest archive, confirm `level.dat` exists) also hasn't
been done yet.

## Joining the server

Server address: `crocsmc.my.id` (or the VPS's public IP if DNS is down).
Because the server is offline-mode:

- **First time joining:** `/register <password> <password>`
- **Every time after:** `/login <password>`

Players should pick a password only they know — that password is what
actually protects their username now that Mojang verification is off.

## Troubleshooting

| Symptom | Likely cause / what to check |
|---|---|
| Server keeps restarting / never reaches "Done" | `docker compose logs mc` — look for a `manage-users`/Playerdb error. Usually a username in `OPS` or `WHITELIST` that doesn't resolve on Mojang (only matters in online mode; this project currently manages ops live via RCON instead). |
| "Connection refused" from players | Check `docker inspect mc --format '{{.RestartCount}}'` — a climbing count means it's crash-looping (see above), not actually listening. |
| Can't join at all in offline mode, no error shown | Check `enforce-secure-profile` in `data/server.properties` — must be `false` when `ONLINE_MODE=FALSE`, otherwise clients without a Mojang-signed chat key are rejected. |
| DNS/port issues | Run `./check.sh`. If the domain fails but `nc -vz <public-ip> 25565` works, it's a DNS problem, not the server. |
| `.env` change doesn't seem to apply | You used `docker compose restart` instead of `docker compose up -d`. Only `up -d` re-reads `.env`. |
| Out of memory / swapping | Lower `MC_MEMORY` in `.env`, then `docker compose up -d`. Leave ~2GB for the OS on this host. |
