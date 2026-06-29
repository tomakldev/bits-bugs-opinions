# Security Model

This document describes what this Docker setup actually protects, where it fails, and when you need a fundamentally different approach.

## Objective

Protect Python and Next.js source code from a client who has root access on the machine running the application.

## Threat model

**Who we're modeling**: a client who:
- Has full root access to the host server
- Can run arbitrary Docker commands (pull, inspect, save, exec)
- Has SSH or physical access to the machine
- May be technically sophisticated (developer or sysadmin level)

**What we're protecting**:
- Python backend source code (`.py` files)
- Next.js frontend source code (`.ts`/`.tsx` files and business logic)

**What we're NOT protecting**:
- Data the application processes at runtime
- Secrets in environment variables (those are the client's problem)
- The public API surface of the application
- Network traffic (use TLS separately at the load balancer)

---

## Controls implemented

### 1. Private container registry

Images live in a registry you control (AWS ECR, GCR, GitHub Container Registry). The client receives time-limited pull-only credentials.

**What it stops**: The client cannot access images without credentials you provide. Before they pull the image, the source code does not exist on their machine.

**Where it breaks down**: Once the image is pulled and cached (`/var/lib/docker/image/` and `/var/lib/docker/overlay2/`), pull credentials are no longer needed to access the cached data. Revoking credentials does not delete the cached image.

A root user can extract everything in a pulled image:

```bash
docker save myapp/backend:latest -o image.tar
mkdir extracted && tar -xf image.tar -C extracted/
find extracted -name '*.tar' -exec tar -xf {} -C extracted/ \;
# All source files are now in extracted/
```

### 2. No interactive shell in runtime image

The runtime container uses `python:3.12-slim` with `bash` removed. There is no package manager available inside the running container.

**What it stops**: `docker exec -it container bash` fails. Casual interactive exploration via docker exec does not work.

**Where it breaks down**: Root on the host can bypass the container's user-space entirely:

```bash
# Enter the container's mount namespace from the host — no shell in container needed
PID=$(docker inspect -f '{{.State.Pid}}' myapp-backend-1)
nsenter -t "$PID" --mount -- cat /app/main.py
```

Root can also read the overlay filesystem directly without any container tools:

```bash
# Find the container's merged layer
cat /var/lib/docker/overlay2/<LAYER_HASH>/merged/app/main.py
```

No shell inside the container does not prevent either of these.

### 3. Non-root container user

The application process runs as UID 1001 inside the container.

**What it stops**: Container breakout attempts requiring root inside the container. Limits damage from application-level code execution vulnerabilities.

**Where it breaks down**: Host root can read the container's files regardless of what UID the process inside runs as. This control addresses lateral movement within the container, not host-level inspection.

### 4. Read-only container filesystem

`read_only: true` in `docker-compose.yml` mounts the container root filesystem read-only. A `tmpfs` provides a writable `/tmp`.

**What it stops**: The application (or an attacker who gets code execution inside the container) writing malicious files to the container layer.

**Where it breaks down**: Does not protect source code. Only restricts what the container process writes.

### 5. Dropped Linux capabilities

`cap_drop: ALL` removes all Linux capabilities. `no-new-privileges: true` prevents privilege escalation via setuid binaries.

**What it stops**: Container-internal privilege escalation. Reduces the risk from container escape exploits that need specific capabilities like `CAP_NET_ADMIN` or `CAP_SYS_PTRACE`.

**Where it breaks down**: These restrictions apply to processes inside the container. They do not restrict what root on the host can do.

### 6. License validation at startup

The backend calls a license server you control before accepting any traffic. If the call fails or returns invalid, the process exits immediately.

**What it stops**:
- Running the application after contract termination (you control the license server response)
- Unauthorized deployment to additional machines (each machine ID gets validated)
- Continued use during a billing dispute

**Where it breaks down**: This is a runtime operational control, not a code protection control. It does not prevent someone from extracting and reading the source. A network-blocking client can prevent the app from starting (intentional), and a determined attacker with extracted source could remove the check and rebuild. Most effective when combined with credential rotation and a legal agreement.

---

## What a root user CAN do

With root on the host and Docker access, a determined attacker can:

```bash
# Extract the entire image filesystem
docker save myapp/backend:latest | tar x -C /tmp/image/
find /tmp/image -name '*.tar' -exec tar -C /tmp/image/ -xf {} \;

# Enter a running container's filesystem without any shell in the container
PID=$(docker inspect -f '{{.State.Pid}}' myapp-backend-1)
nsenter -t "$PID" --mount -- find /app -type f

# Read the overlay filesystem directly from the host
ls /var/lib/docker/overlay2/
```

**No Docker-only solution prevents this.** Container images are not encrypted at rest on the host filesystem. This is a fundamental property of how Linux containers and the overlay filesystem work, not a Docker bug or misconfiguration.

---

## Bytecode compilation — why it's not implemented

A common suggestion: compile `.py` to `.pyc` and remove source files. We don't implement it. Python bytecode is trivially decompiled:

```bash
pip install uncompyle6
uncompyle6 main.cpython-312.pyc  # readable Python in seconds
```

Tools like `uncompyle6`, `decompile3`, and `pycdc` reconstruct human-readable Python from bytecode in seconds. This is obfuscation, not protection. It adds 10 minutes of effort for an attacker while adding real complexity to your build pipeline. The security outcome is the same.

---

## What actually provides stronger guarantees

### SaaS / remote execution

Run the application on your own infrastructure. The client accesses it over HTTPS. Nothing runs on their machine — nothing to extract.

**Limitations**: latency for on-premise requirements, data residency and compliance constraints, uptime dependency on your infrastructure.

**Best for**: web-based products where persistent network access is guaranteed and data doesn't need to stay on-premise.

### Confidential computing

Run the workload inside a Trusted Execution Environment (TEE):
- **AWS Nitro Enclaves** — isolated VMs on EC2, no persistent storage, no SSH, attested code execution
- **Intel SGX** — encrypted memory enclaves, verifiable via remote attestation
- **AMD SEV-SNP** — encrypted VM memory, inaccessible to hypervisor or host OS

Code and memory inside a TEE are encrypted at hardware level. Host root cannot read enclave memory. The hardware enforces this.

**Limitations**: requires specific hardware or cloud environment, significant operational complexity, limited workload types, attestation infrastructure needed.

**Best for**: high-value IP in regulated environments where the client's hardware must be used.

### Legal controls

Combine technical controls with a binding license agreement that prohibits reverse engineering, decompilation, and redistribution. This doesn't prevent a technical attack but provides legal recourse and may be sufficient deterrent for commercial clients who want to keep their software contracts.

---

## Realistic expectations

| Control | Stops casual user | Stops IT admin with root | Stops security researcher |
|---|---|---|---|
| Private registry | Yes | Yes (before pull) | Yes (before pull) |
| No shell in container | Yes | No | No |
| Non-root process | Yes | No | No |
| Read-only filesystem | Yes | No | No |
| License check | Yes | Partially | No |
| SaaS model | Yes | Yes | Yes |
| Confidential computing | Yes | Yes | Yes (if correctly set up) |

## Summary

This setup materially raises the effort required to access source code. It stops casual inspection and makes accidental exposure unlikely. It does not, and cannot, stop a technically capable root user who is determined to extract the code.

If code protection is a hard requirement and the client's machine must be used, the architecturally correct solution is confidential computing. If some latency is acceptable, a SaaS model is simpler and more reliable.

For most ISV scenarios — where the client is a business, not an adversary, and the risk is accidental copying rather than deliberate theft — this setup combined with a solid license agreement is a reasonable, practical choice.
