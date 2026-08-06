# WSL Foundation to Server Extension Contract

`bootstrap-wsl-ai-dev` is Phase 1. `bootstrap-wsl-server` is Phase 2 and must run after the foundation is healthy.

## Phase 1 owns

- WSL distribution discovery, command-origin audit, native developer tools, and optional Windows PATH isolation.
- `/etc/wsl.conf` foundation keys: `[boot] systemd=true` and `[user] default=WSL_USER`.
- Optional `[interop] appendWindowsPath=false`; explicit Windows interop remains available through absolute paths.
- Default WSL NAT networking and the generated `/etc/resolv.conf` baseline. Do not enable mirrored networking as a shortcut.
- Git/GitLab/GitHub client configuration, AI CLI authentication, Docker installation and Docker-specific proxy decisions.
- Windows AI cleanup and Explorer integration.

## Handoff contract

Before invoking `bootstrap-wsl-server`, record and verify:

- WSL distribution name and Linux login user.
- Windows profile name and current Windows hostname.
- `systemd` is PID 1 after `wsl --shutdown`.
- `ip -4 route show default` returns a route and `/etc/resolv.conf` has a nameserver.
- The selected WSL user exists and has a shell.
- Node.js is installed if the optional workbench is requested.

## Phase 2 owns

- OpenSSH server policy and `~/.ssh/authorized_keys` for server access.
- Windows SSH `portproxy`, Private/LocalSubnet firewall rule, and WSL logon startup task.
- Loopback-only workbench, health timer, host manual, and client manual.

## Do not cross ownership boundaries

- The server extension must not alter `.wslconfig`, mirrored networking, global WSL DNS, Docker daemon proxy, GitHub/GitLab client hosts, Windows AI installations, or Explorer registry state.
- The foundation must not expose LAN ports, edit `sshd_config`, enroll `authorized_keys`, or expose the workbench.
- Both phases must preserve unrelated `/etc/wsl.conf` sections and require `wsl --shutdown` after changes that affect WSL startup.

## Safe shared state

| State | Owner | Extension behavior |
|---|---|---|
| `/etc/wsl.conf` `[interop]` | AI foundation | Read and preserve |
| `/etc/wsl.conf` `[boot]`, `[user]` | AI foundation | Verify; idempotent fallback only if foundation is unavailable |
| `/etc/wsl.conf` `[network]`, `[wsl2]` | Network decision layer | Never rewrite during server setup |
| `~/.ssh/config` and client keys | AI foundation/user | Read only |
| `~/.ssh/authorized_keys` and `sshd_config.d/99-wsl-server.conf` | Server extension | Manage server authentication only |
| Docker service and proxy | AI foundation | Observe only |

