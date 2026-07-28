# Agentic Workflows

## Selected model runtime

SilverBrick is the dedicated LLM machine:

- Windows with NVIDIA GeForce RTX 4060, 8 GB VRAM;
- LM Studio with its OpenAI-compatible API;
- Tailscale address `100.91.171.26`;
- initial tool-capable model `qwen/qwen3.5-9b`, local Q4_K_M GGUF;
- additional local embedding models are available but are not selected for the first workflow.

The HP Server remains the orchestration host. Monitoring, backups, DNS, and administration must continue working when SilverBrick is asleep.

## Network and authentication contract

The intended API URL is:

```text
http://100.91.171.26:1234/v1
```

LM Studio must bind to the SilverBrick Tailscale address, not `0.0.0.0`. Require Authentication must be enabled and a dedicated token must be created for the HP Server. The token is stored only in `/etc/homelab/agents.env` with `root:root` ownership and mode `0600`.

Do not create a Cloudflare DNS record or Caddy route for the model API. It is a machine-to-machine dependency, not a family-facing service.

Windows Firewall restricts TCP 1234 on `100.91.171.26` to source `100.65.83.35` (HP Server). Reapply the versioned `scripts/windows/restrict-lm-studio-firewall.ps1` on SilverBrick if either Tailscale address changes. The script disables broader inbound LM Studio or TCP 1234 allow rules before creating the scoped rule.

## SilverBrick setup

In LM Studio:

1. Open **Developer** and **Server Settings**.
2. Enable **Require Authentication**.
3. Open **Manage Tokens** and create a dedicated token named `hp-server-agent` with inference/model-list access only.
4. Keep CORS disabled and do not enable unrestricted Remote MCP tools.
5. Keep Just-In-Time loading enabled if SilverBrick should release VRAM while idle.
6. Stop and restart the server bound to `100.91.171.26` on port `1234`.

The CLI equivalent for the final server start is:

```powershell
lms server stop
lms server start --bind 100.91.171.26 --port 1234
```

Authentication must be enabled in the LM Studio UI before exposing a non-local bind.

## HP Server secret handoff

Create `/etc/homelab/agents.env` from `config/agents.env.example`, insert the token interactively, and protect the file:

```bash
sudo install -d -m 0700 /etc/homelab
sudo install -m 0600 -o root -g root config/agents.env.example /etc/homelab/agents.env
sudoedit /etc/homelab/agents.env
```

Never paste the token into Git, chat, a command argument, or shell history.

After the server and token are ready:

```bash
make check-lm-studio
```

The check calls only `/v1/models`, verifies authentication and the configured model identifier, deletes its temporary response, and prints `LM_STUDIO_API_OK` without printing the token.

The first authenticated HP Server to SilverBrick check completed successfully on 2026-07-28:

```text
LM_STUDIO_API_OK
```

An unauthenticated request from the HP Server returned HTTP 401 as expected. The Windows Firewall source restriction remains a separate safety-gated task.

## Implementation order

1. Verify the authenticated Tailscale-only LM Studio API.
2. Add Open WebUI on the HP Server as the private family AI interface.
3. Add a minimal Python agent runtime with one read-only `homelab_status` tool.
4. Add structured tests for tool selection, timeouts, and malformed model output.
5. Add approval persistence before any state-changing tool.
6. Build the Calibre librarian and family media-request workflows.

Do not give the model a Docker socket, shell, filesystem root, secrets, or arbitrary HTTP access. Each tool must be a narrow wrapper with explicit input validation and a bounded timeout.
