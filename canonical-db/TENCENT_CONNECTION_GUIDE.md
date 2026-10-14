# Tencent Cloud SSH connection guide

## Current check

- Host: `1.12.77.180`
- SSH port 22 responds.
- Verified ED25519 host fingerprint: `SHA256:QzSzzs9PHpgxQ97LrYgjzLMVXTjQHQrrceogacOVcF8`
- Unauthenticated checks for both `root` and `ubuntu` return `Permission denied (publickey,password)`.
- No SSH terminal or Tencent console tab is attached to the current Codex window.
- PostgreSQL port 5432 is not publicly reachable and should remain closed.

## Recommended one-time connection setup

1. In PowerShell, create a dedicated key if one does not already exist:

   ```powershell
   ssh-keygen -t ed25519 -a 100 -f "$env:USERPROFILE\.ssh\phoenix_tencent" -C "phoenix-canonical-deploy"
   Get-Content "$env:USERPROFILE\.ssh\phoenix_tencent.pub"
   ```

2. In the Tencent Cloud console, use the server's VNC/login facility or key-management page to add only that public key to the intended Linux account. Prefer a dedicated deployment account or `ubuntu`; do not send the private key through chat.

3. Restrict the Tencent security-group rule for TCP 22 to the current administrator public IP. Keep TCP 5432 closed. Ports 80/443 may remain assigned to the existing nginx service.

4. Add this local SSH configuration:

   ```text
   Host phoenix-tencent
     HostName 1.12.77.180
     User ubuntu
     IdentityFile ~/.ssh/phoenix_tencent
     IdentitiesOnly yes
   ```

5. Connect and compare the displayed host fingerprint before accepting it:

   ```powershell
   ssh phoenix-tencent
   ```

   It must equal `SHA256:QzSzzs9PHpgxQ97LrYgjzLMVXTjQHQrrceogacOVcF8`.

6. Verify the non-destructive server inventory:

   ```bash
   hostname
   uname -srmo
   docker version
   docker compose version
   docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
   ss -lnt
   df -h
   ```

After `ssh phoenix-tencent` succeeds from this machine, Codex can perform the inventory, upload the prepared package, create new secrets on the server, deploy, run health checks, and verify backup/restore without exposing PostgreSQL publicly.
