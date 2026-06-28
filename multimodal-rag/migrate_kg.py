"""One-time migration: consolidate predicates, move properties to JSONB, classify entity types."""

import json
import sys
from db import get_conn
from knowledge_graph import (
    PREDICATE_ALIASES,
    PROPERTY_PREDICATES,
    infer_entity_type,
)

def migrate():
    conn = get_conn()
    cur = conn.cursor()

    # ── 1. Consolidate predicate aliases ────────────────────────────────────
    print("=== Phase 1: Predicate consolidation ===")
    for old_pred, new_pred in PREDICATE_ALIASES.items():
        cur.execute("SELECT COUNT(*) FROM kg_triples WHERE predicate = %s", (old_pred,))
        count = cur.fetchone()[0]
        if count > 0:
            # Check for duplicates: existing active triple with same (subject, new_pred, object)
            cur.execute(
                """SELECT t1.id, t1.subject, t1.object
                   FROM kg_triples t1
                   WHERE t1.predicate = %s AND t1.valid_to IS NULL
                     AND EXISTS (
                       SELECT 1 FROM kg_triples t2
                       WHERE t2.subject = t1.subject AND t2.object = t1.object
                         AND t2.predicate = %s AND t2.valid_to IS NULL AND t2.id != t1.id
                     )""",
                (old_pred, new_pred),
            )
            dupes = cur.fetchall()
            if dupes:
                dupe_ids = [d[0] for d in dupes]
                print(f"  {old_pred} -> {new_pred}: {count} triples, {len(dupe_ids)} would be duplicates (expiring)")
                for dupe_id in dupe_ids:
                    cur.execute("UPDATE kg_triples SET valid_to = CURRENT_DATE::text WHERE id = %s", (dupe_id,))
                # Rename the non-duplicate ones
                cur.execute(
                    """UPDATE kg_triples SET predicate = %s
                       WHERE predicate = %s AND valid_to IS NULL""",
                    (new_pred, old_pred),
                )
            else:
                cur.execute("UPDATE kg_triples SET predicate = %s WHERE predicate = %s", (new_pred, old_pred))
                print(f"  {old_pred} -> {new_pred}: {count} triples renamed")
        else:
            print(f"  {old_pred} -> {new_pred}: 0 triples (skip)")

    # ── 2. Move property predicates to entity JSONB ─────────────────────────
    print("\n=== Phase 2: Property predicates -> entity JSONB ===")
    for pred, prop_key in PROPERTY_PREDICATES.items():
        cur.execute(
            "SELECT id, subject, object FROM kg_triples WHERE predicate = %s AND valid_to IS NULL",
            (pred,),
        )
        rows = cur.fetchall()
        if not rows:
            print(f"  {pred} -> .{prop_key}: 0 triples (skip)")
            continue
        for triple_id, subject, obj in rows:
            # Store as property
            cur.execute(
                "UPDATE kg_entities SET properties = properties || %s::jsonb WHERE name = %s",
                (json.dumps({prop_key: obj}), subject),
            )
            # Expire the triple
            cur.execute(
                "UPDATE kg_triples SET valid_to = CURRENT_DATE::text WHERE id = %s",
                (triple_id,),
            )
        print(f"  {pred} -> .{prop_key}: {len(rows)} triples moved to entity properties")

    # ── 3. Classify entity types ────────────────────────────────────────────
    print("\n=== Phase 3: Entity type classification ===")
    cur.execute("SELECT name, type FROM kg_entities WHERE type = 'unknown'")
    unknowns = cur.fetchall()
    classified = 0
    for name, _ in unknowns:
        # Try to infer from name patterns
        etype = infer_entity_type(name)
        if etype != "unknown":
            cur.execute("UPDATE kg_entities SET type = %s WHERE name = %s", (etype, name))
            classified += 1
    # Second pass: infer from predicate context
    cur.execute("SELECT name FROM kg_entities WHERE type = 'unknown'")
    still_unknown = [r[0] for r in cur.fetchall()]
    for name in still_unknown:
        cur.execute(
            "SELECT predicate FROM kg_triples WHERE subject = %s AND valid_to IS NULL LIMIT 1",
            (name,),
        )
        row = cur.fetchone()
        if row:
            etype = infer_entity_type(name, row[0], is_subject=True)
            if etype != "unknown":
                cur.execute("UPDATE kg_entities SET type = %s WHERE name = %s", (etype, name))
                classified += 1
                continue
        cur.execute(
            "SELECT predicate FROM kg_triples WHERE object = %s AND valid_to IS NULL LIMIT 1",
            (name,),
        )
        row = cur.fetchone()
        if row:
            etype = infer_entity_type(name, row[0], is_subject=False)
            if etype != "unknown":
                cur.execute("UPDATE kg_entities SET type = %s WHERE name = %s", (etype, name))
                classified += 1
    print(f"  Classified {classified} of {len(unknowns)} unknown entities")
    cur.execute("SELECT type, COUNT(*) FROM kg_entities GROUP BY type ORDER BY COUNT(*) DESC")
    for etype, count in cur.fetchall():
        print(f"    {etype}: {count}")

    # ── 4. Create new indexes ───────────────────────────────────────────────
    print("\n=== Phase 4: Indexes ===")
    for idx in [
        "CREATE INDEX IF NOT EXISTS idx_kg_triples_valid_to ON kg_triples(valid_to)",
        "CREATE INDEX IF NOT EXISTS idx_kg_triples_valid_from ON kg_triples(valid_from)",
        "CREATE INDEX IF NOT EXISTS idx_kg_triples_predicate ON kg_triples(predicate)",
    ]:
        cur.execute(idx)
        print(f"  {idx.split('idx_')[1].split(' ON')[0]}: OK")

    # ── Summary ─────────────────────────────────────────────────────────────
    print("\n=== Summary ===")
    cur.execute("SELECT COUNT(*) FROM kg_triples WHERE valid_to IS NULL")
    active = cur.fetchone()[0]
    cur.execute("SELECT COUNT(DISTINCT predicate) FROM kg_triples WHERE valid_to IS NULL")
    pred_count = cur.fetchone()[0]
    cur.execute("SELECT DISTINCT predicate FROM kg_triples WHERE valid_to IS NULL ORDER BY predicate")
    preds = [r[0] for r in cur.fetchall()]
    print(f"  Active triples: {active}")
    print(f"  Distinct predicates: {pred_count}")
    print(f"  Predicates: {', '.join(preds)}")

    if "--dry-run" in sys.argv:
        print("\n  DRY RUN: rolling back")
        conn.rollback()
    else:
        conn.commit()
        print("\n  COMMITTED")

    cur.close()
    conn.close()


if __name__ == "__main__":
    migrate()
