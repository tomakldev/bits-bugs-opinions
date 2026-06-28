# NAS File Exchange

Mount: `/mnt/nas` (bind mount to `/home/user/shares`). Windows: `\\YOUR_SERVER_IP\shares\`.

## Key paths

- `/mnt/nas/RAG/` -- drop zone, auto-ingested into pgvector then DELETED
- `/mnt/nas/claude/uploads/` -- files from user's PC (persists)
- `/mnt/nas/claude/logs/` -- log files for analysis (persists)
- `/mnt/nas/claude/scripts/` -- generated scripts for remote servers
- `/mnt/nas/claude/exports/` -- data exports, CSVs
- `/mnt/nas/claude/images/generated/` -- AI-generated images
- `/mnt/nas/claude/azure/` -- ARM templates, Azure configs

## Routing

- "copy to NAS" -> `/mnt/nas/claude/` subfolder
- "check uploaded file" -> `/mnt/nas/claude/uploads/` then `/mnt/nas/claude/logs/`
- Reports, tickets, runbooks -> RAG via `mcp__rag__rag_save` (not disk)
- Use `mcp__filesystem__*` MCP tools over raw Bash for NAS operations
- Stale mount fix: `sudo mount -a`
