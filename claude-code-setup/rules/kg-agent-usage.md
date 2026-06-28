# Knowledge Graph usage for agents

Query KG before investigating any system: `mcp__rag__kg_query(entity="LAPA")`
For full context (KG + related docs): `mcp__rag__kg_query_enriched(entity="LAPA")`
Add facts after discovering infra details: `mcp__rag__kg_add(subject, predicate, object, valid_from)`

## Canonical predicates

Use only these. Old aliases are auto-normalized, but prefer canonical forms:

- `runs_on` (host/platform), `depends_on` (service dependency), `uses` (cloud resources, accounts)
- `built_with` (tech stack), `managed_by` (ownership), `exposed_via` (networking)
- `stores_data_in` (databases), `data_flow` (data movement), `located_in` (geography)
- `code_at`, `config_at` (source/config locations), `deployed_version`, `migrated_to`, `migrated_from`
- `serves` (what a service does), `cert_expires`, `incident`, `change`, `upgraded_to`, `decommissioned`

## Property predicates (stored in entity JSONB, not as triples)

These are auto-routed to entity properties: `has_ip`, `has_rpo`, `has_rto`, `has_version`, `has_account_id`, `has_servicenow_id`, `has_drp_priority`, `uses_port`.
Example: `kg_add("LAPA", "has_ip", "10.0.1.5")` stores `{"ip": "10.0.1.5"}` in LAPA's properties.

## Entity types

Entities are auto-classified on creation: service, host, container, database, cloud_resource, person, organization, network, config. Override by updating the entity directly if the auto-classification is wrong.

## Entity naming

Proper case, consistent: "LAPA", "SJK", "MC-SJK-PROD10". Services uppercase, hosts as-is.

## Staleness checks

Run `mcp__rag__kg_stale(days=90)` periodically to find facts that may need review.
