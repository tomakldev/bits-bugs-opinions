"""PostgreSQL-backed temporal knowledge graph for entity-relationship tracking."""

from datetime import date, timedelta
from db import get_conn
import json

# ── Predicate normalization ─────────────────────────────────────────────────
# Aliases map non-canonical predicates to their canonical form.
# Canonical predicates are the ~15 we actually want in the KG.
PREDICATE_ALIASES = {
    "runs": "runs_on",
    "hosted_on": "runs_on",
    "connects_to": "depends_on",
    "owned_by": "managed_by",
    "publishes_to": "data_flow",
    "exports_to": "data_flow",
    "source_code_at": "code_at",
    "uses_account": "uses",
    "uses_tenant": "uses",
    "uses_subscription": "uses",
    "uses_region": "uses",
    "uses_registry": "uses",
    "uses_resource_group": "uses",
}

# Property-like predicates whose object should be stored in entity JSONB
# instead of as a triple. The key in properties is the predicate minus "has_".
PROPERTY_PREDICATES = {
    "has_ip": "ip",
    "has_rpo": "rpo",
    "has_rto": "rto",
    "has_version": "version",
    "has_account_id": "account_id",
    "has_servicenow_id": "servicenow_id",
    "has_drp_priority": "drp_priority",
    "uses_port": "port",
}

CANONICAL_PREDICATES = [
    "runs_on", "depends_on", "uses", "built_with", "managed_by",
    "exposed_via", "stores_data_in", "data_flow", "located_in",
    "code_at", "config_at", "deployed_version", "migrated_to",
    "migrated_from", "decommissioned", "incident", "change",
    "upgraded_to", "serves", "replaced_api_gateway",
    "cert_expires", "is_type", "role_at", "freelances_for",
    "drp_updated", "patching_completed", "azure_alerts_created",
    "performance_regression_started", "remaining_sections",
    "last_pushed_section", "ad_vendor",
]


def normalize_predicate(predicate):
    """Map aliases to canonical predicates."""
    return PREDICATE_ALIASES.get(predicate, predicate)


def is_property_predicate(predicate):
    """Check if a predicate should be stored as entity property instead of triple."""
    return predicate in PROPERTY_PREDICATES


# ── Entity type inference ───────────────────────────────────────────────────
# Patterns to guess entity type from name. Checked in order, first match wins.
ENTITY_TYPE_PATTERNS = [
    # Cloud resources
    (["azure", "aws", "s3", "ec2", "lambda", "rds", "app service", "aks", "acr"], "cloud_resource"),
    # Databases
    (["postgres", "mongodb", "redis", "mysql", "cosmosdb", "db", "database", "pgvector"], "database"),
    # Containers / orchestration
    (["docker", "container", "microk8s", "kubernetes", "k8s", "helm"], "container"),
    # Network
    (["vlan", "subnet", "vpn", "wireguard", "cloudflare", "tunnel", "er605", "eap", "omada"], "network"),
    # Hosts
    (["srv-", "mc-", "192.168.", "10.0.", "ubuntu", "rhel", "wyse"], "host"),
    # People
    (["tomasz", "tomek", "cgi", "posti"], "person"),
    # Organizations
    (["gulermak", "finland", "poland"], "organization"),
]

# Predicates that hint at subject/object types
PREDICATE_TYPE_HINTS = {
    "runs_on": (None, "host"),
    "stores_data_in": (None, "database"),
    "managed_by": (None, "person"),
    "deployed_version": ("service", None),
    "exposed_via": (None, "network"),
    "built_with": ("service", None),
    "serves": ("service", None),
    "depends_on": ("service", None),
}


def infer_entity_type(name, predicate=None, is_subject=True):
    """Guess entity type from name patterns and predicate context."""
    lower = name.lower()
    for patterns, etype in ENTITY_TYPE_PATTERNS:
        if any(p in lower for p in patterns):
            return etype
    # Use predicate hint if no pattern matched
    if predicate and predicate in PREDICATE_TYPE_HINTS:
        subj_type, obj_type = PREDICATE_TYPE_HINTS[predicate]
        hint = subj_type if is_subject else obj_type
        if hint:
            return hint
    return "unknown"


# ── DB init ─────────────────────────────────────────────────────────────────

def _init_db():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS kg_entities (
                    id SERIAL PRIMARY KEY,
                    name TEXT NOT NULL UNIQUE,
                    type TEXT NOT NULL DEFAULT 'unknown',
                    properties JSONB DEFAULT '{}'
                );
                CREATE TABLE IF NOT EXISTS kg_triples (
                    id SERIAL PRIMARY KEY,
                    subject TEXT NOT NULL,
                    predicate TEXT NOT NULL,
                    object TEXT NOT NULL,
                    valid_from TEXT,
                    valid_to TEXT,
                    confidence REAL DEFAULT 1.0,
                    source_drawer_id TEXT,
                    created_at TIMESTAMPTZ DEFAULT now()
                );
                CREATE INDEX IF NOT EXISTS idx_kg_triples_subject ON kg_triples(subject);
                CREATE INDEX IF NOT EXISTS idx_kg_triples_object ON kg_triples(object);
                CREATE INDEX IF NOT EXISTS idx_kg_triples_valid_to ON kg_triples(valid_to);
                CREATE INDEX IF NOT EXISTS idx_kg_triples_valid_from ON kg_triples(valid_from);
                CREATE INDEX IF NOT EXISTS idx_kg_triples_predicate ON kg_triples(predicate);
            """)
        conn.commit()


_init_done = False


def _ensure_init():
    global _init_done
    if not _init_done:
        _init_db()
        _init_done = True


def _ensure_entity(cur, name, entity_type="unknown"):
    """Create entity if missing. If type is 'unknown' and entity exists, don't overwrite."""
    if entity_type != "unknown":
        cur.execute(
            """INSERT INTO kg_entities (name, type) VALUES (%s, %s)
               ON CONFLICT (name) DO UPDATE SET type = EXCLUDED.type
               WHERE kg_entities.type = 'unknown'""",
            (name, entity_type),
        )
    else:
        cur.execute(
            "INSERT INTO kg_entities (name, type) VALUES (%s, %s) ON CONFLICT (name) DO NOTHING",
            (name, entity_type),
        )


def _set_entity_property(cur, entity_name, key, value):
    """Store a property in entity JSONB instead of as a triple."""
    cur.execute(
        """UPDATE kg_entities SET properties = properties || %s::jsonb WHERE name = %s""",
        (json.dumps({key: value}), entity_name),
    )


def add_triple(subject, predicate, obj, valid_from=None, confidence=1.0, source_drawer_id=None):
    _ensure_init()
    predicate = normalize_predicate(predicate)

    # Property predicates go into entity JSONB, not as triples
    if is_property_predicate(predicate):
        prop_key = PROPERTY_PREDICATES[predicate]
        with get_conn() as conn:
            with conn.cursor() as cur:
                subj_type = infer_entity_type(subject, predicate, is_subject=True)
                _ensure_entity(cur, subject, subj_type)
                _set_entity_property(cur, subject, prop_key, obj)
            conn.commit()
        return -1  # Signal: stored as property, not a triple

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM kg_triples WHERE subject=%s AND predicate=%s AND object=%s AND valid_to IS NULL",
                (subject, predicate, obj),
            )
            existing = cur.fetchone()
            if existing:
                return existing[0]

            subj_type = infer_entity_type(subject, predicate, is_subject=True)
            obj_type = infer_entity_type(obj, predicate, is_subject=False)
            _ensure_entity(cur, subject, subj_type)
            _ensure_entity(cur, obj, obj_type)
            cur.execute(
                """INSERT INTO kg_triples (subject, predicate, object, valid_from, confidence, source_drawer_id)
                   VALUES (%s, %s, %s, %s, %s, %s) RETURNING id""",
                (subject, predicate, obj, valid_from, confidence, source_drawer_id),
            )
            triple_id = cur.fetchone()[0]
        conn.commit()
    return triple_id


def query_entity(name, direction="both", as_of=None):
    _ensure_init()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, type, properties FROM kg_entities WHERE name=%s", (name,))
            row = cur.fetchone()
            if not row:
                return {"entity": None, "triples": []}
            entity = {"id": row[0], "name": row[1], "type": row[2], "properties": row[3]}

            triples = []
            cols = ["id", "subject", "predicate", "object", "valid_from", "valid_to", "confidence", "source_drawer_id", "created_at"]
            select = "SELECT id, subject, predicate, object, valid_from, valid_to, confidence, source_drawer_id, created_at FROM kg_triples"

            if direction in ("both", "outgoing"):
                if as_of:
                    cur.execute(select + " WHERE subject=%s AND (valid_to IS NULL OR valid_to >= %s)", (name, as_of))
                else:
                    cur.execute(select + " WHERE subject=%s", (name,))
                triples.extend(dict(zip(cols, r)) for r in cur.fetchall())
            if direction in ("both", "incoming"):
                if as_of:
                    cur.execute(select + " WHERE object=%s AND (valid_to IS NULL OR valid_to >= %s)", (name, as_of))
                else:
                    cur.execute(select + " WHERE object=%s", (name,))
                triples.extend(dict(zip(cols, r)) for r in cur.fetchall())

    # Convert datetime objects to strings
    for t in triples:
        if t.get("created_at"):
            t["created_at"] = str(t["created_at"])

    return {"entity": entity, "triples": triples}


def invalidate_triple(triple_id, valid_to=None):
    _ensure_init()
    vto = valid_to or date.today().isoformat()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE kg_triples SET valid_to=%s WHERE id=%s", (vto, triple_id))
        conn.commit()
    return True


def get_timeline(entity=None):
    _ensure_init()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cols = ["id", "subject", "predicate", "object", "valid_from", "valid_to", "confidence", "source_drawer_id", "created_at"]
            if entity:
                cur.execute(
                    """SELECT id, subject, predicate, object, valid_from, valid_to, confidence, source_drawer_id, created_at
                       FROM kg_triples WHERE subject=%s OR object=%s
                       ORDER BY COALESCE(valid_from, created_at::text)""",
                    (entity, entity),
                )
            else:
                cur.execute(
                    """SELECT id, subject, predicate, object, valid_from, valid_to, confidence, source_drawer_id, created_at
                       FROM kg_triples ORDER BY COALESCE(valid_from, created_at::text)"""
                )
            rows = [dict(zip(cols, r)) for r in cur.fetchall()]

    for r in rows:
        if r.get("created_at"):
            r["created_at"] = str(r["created_at"])
    return rows


def get_stats():
    _ensure_init()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM kg_entities")
            entities = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM kg_triples")
            total = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL")
            active = cur.fetchone()[0]
            cur.execute("SELECT DISTINCT predicate FROM kg_triples")
            predicates = [r[0] for r in cur.fetchall()]
    return {
        "entities": entities,
        "total_triples": total,
        "active_triples": active,
        "expired_triples": total - active,
        "predicates": predicates,
    }


def get_stale(days=90):
    """Return active triples with valid_from older than N days."""
    _ensure_init()
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    with get_conn() as conn:
        with conn.cursor() as cur:
            cols = ["id", "subject", "predicate", "object", "valid_from", "valid_to", "confidence", "created_at"]
            cur.execute(
                """SELECT id, subject, predicate, object, valid_from, valid_to, confidence, created_at
                   FROM kg_triples
                   WHERE valid_to IS NULL
                     AND valid_from IS NOT NULL
                     AND valid_from < %s
                   ORDER BY valid_from""",
                (cutoff,),
            )
            rows = [dict(zip(cols, r)) for r in cur.fetchall()]
    for r in rows:
        if r.get("created_at"):
            r["created_at"] = str(r["created_at"])
    return rows
