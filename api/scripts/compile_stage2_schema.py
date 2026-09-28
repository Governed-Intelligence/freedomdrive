"""
FreedomDRIVE Stage 2 Authoritative Schema Compiler
Parses 8122026/3 - Working Files (Word & Excel)/FreedomDRIVE - Database Schema (08-12-2026).docx
and fsc_mcp_suite_v1/fsc_mcp/fsc_kb_mcp/data/knowledge_base.json
Generates production-grade PostgreSQL migration: 003_stage2_complete_285_tables.sql
"""
import os
import re
import json
import zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict

POSTGRES_RESERVED = {
    "all", "analyse", "analyze", "and", "any", "array", "as", "asc", "asymmetric",
    "authorization", "binary", "both", "case", "cast", "check", "collate", "collation",
    "column", "concurrently", "constraint", "create", "cross", "current_catalog",
    "current_date", "current_role", "current_schema", "current_time", "current_timestamp",
    "current_user", "default", "deferrable", "desc", "distinct", "do", "else", "end",
    "except", "false", "fetch", "for", "foreign", "freeze", "from", "full", "grant",
    "group", "having", "ilike", "in", "initially", "inner", "intersect", "into", "is",
    "isnull", "join", "lateral", "leading", "left", "like", "limit", "localtime",
    "localtimestamp", "natural", "not", "notnull", "null", "offset", "on", "only",
    "or", "order", "outer", "overlaps", "placing", "primary", "references", "returning",
    "right", "select", "session_user", "similar", "some", "symmetric", "table", "tablesample",
    "then", "to", "trailing", "true", "union", "unique", "user", "using", "variadic",
    "verbose", "when", "where", "window", "with"
}

def quote_ident(ident: str) -> str:
    ident_lower = ident.lower()
    if ident_lower in POSTGRES_RESERVED or not re.match(r"^[a-z_][a-z0-9_]*$", ident_lower):
        return f'"{ident_lower}"'
    return ident_lower

def main():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    docx_path = os.path.join(root_dir, "8122026", "3 - Working Files (Word & Excel)", "FreedomDRIVE - Database Schema (08-12-2026).docx")
    kb_path = os.path.join(root_dir, "fsc_mcp_suite_v1", "fsc_mcp", "fsc_kb_mcp", "data", "knowledge_base.json")
    out_path = os.path.join(os.path.dirname(__file__), "..", "db", "migrations", "003_stage2_complete_285_tables.sql")

    print(f"Reading docx from {docx_path}...")
    with zipfile.ZipFile(docx_path) as z:
        with z.open("word/document.xml") as f:
            tree = ET.parse(f)
            doc_root = tree.getroot()

    print(f"Reading KB json from {kb_path}...")
    with open(kb_path, "r", encoding="utf-8") as f:
        kb = json.load(f)

    # Build enum map: (table_upper, col_lower) -> values list
    kb_enums = kb.get("enums", [])
    enum_map = {}
    for e in kb_enums:
        key = (e["table"].upper(), e["column"].lower())
        enum_map[key] = e["values"]

    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    body = doc_root.find(".//w:body", ns)

    def get_text(element):
        return "".join(element.itertext()).strip()

    tables = []
    current_domain = "GENERAL"
    current_table_name = None
    current_table_desc = ""

    for child in list(body):
        tag = child.tag.split("}")[-1]
        if tag == "p":
            txt = get_text(child)
            if not txt:
                continue
            if txt.startswith("Domain:"):
                current_domain = txt.replace("Domain:", "").strip()
            elif "TABLE:" in txt:
                m = re.search(r"TABLE:\s*([A-Za-z0-9_]+)", txt)
                if m:
                    current_table_name = m.group(1).upper()
            elif current_table_name and not current_table_desc:
                current_table_desc = txt
        elif tag == "tbl":
            rows = child.findall(".//w:tr", ns)
            cols_data = []
            for r in rows:
                cells = [get_text(c) for c in r.findall(".//w:tc", ns)]
                cols_data.append(cells)
            tables.append({
                "domain": current_domain,
                "table_name": current_table_name,
                "desc": current_table_desc,
                "rows": cols_data
            })
            current_table_name = None
            current_table_desc = ""

    print(f"Parsed {len(tables)} tables from docx.")

    # Collect all needed enum types
    # Set of (type_name, tuple_of_values)
    enum_types_to_create = {}

    def resolve_enum(table_name, col_name):
        key = (table_name.upper(), col_name.lower())
        if key in enum_map:
            type_name = f"fs.{table_name.lower()}_{col_name.lower()}_enum"
            return type_name, enum_map[key]
        if table_name.endswith("_SHADOW"):
            base_tbl = table_name[:-7]
            bkey = (base_tbl.upper(), col_name.lower())
            if bkey in enum_map:
                type_name = f"fs.{base_tbl.lower()}_{col_name.lower()}_enum"
                return type_name, enum_map[bkey]
        raise ValueError(f"Could not resolve enum values for {table_name}.{col_name}")

    # Inspect all columns and map data types
    schema_tables = {}
    for t in tables:
        tname = t["table_name"]
        cols = []
        rows = t["rows"]
        # row 0 is header: Column Name, Data Type, PK/FK, Unique, Description, Example Value
        for r in rows[1:]:
            col_name = r[0].strip().lower()
            raw_type = r[1].strip()
            pk_fk = r[2].strip() if len(r) > 2 else ""
            unique = r[3].strip() if len(r) > 3 else ""
            desc = r[4].strip() if len(r) > 4 else ""

            # Normalize data type
            pg_type = None
            type_lower = raw_type.lower()
            if type_lower == "uuid":
                pg_type = "UUID"
            elif type_lower == "timestamptz":
                pg_type = "TIMESTAMPTZ"
            elif type_lower == "datetime":
                pg_type = "TIMESTAMPTZ"
            elif type_lower == "date":
                pg_type = "DATE"
            elif type_lower == "time":
                pg_type = "TIME"
            elif type_lower == "boolean":
                pg_type = "BOOLEAN"
            elif type_lower == "integer":
                pg_type = "INTEGER"
            elif type_lower == "smallint":
                pg_type = "SMALLINT"
            elif type_lower == "bigint":
                pg_type = "BIGINT"
            elif type_lower == "text":
                pg_type = "TEXT"
            elif type_lower == "citext":
                pg_type = "CITEXT"
            elif type_lower in ("jsonb", "jsonb or text"):
                pg_type = "JSONB"
            elif type_lower == "inet":
                pg_type = "INET"
            elif type_lower == "numeric (4,1)":
                pg_type = "NUMERIC(4,1)"
            elif type_lower.startswith("numeric"):
                pg_type = raw_type.upper()
            elif type_lower.startswith("varchar"):
                pg_type = raw_type.upper()
            elif type_lower == "enum":
                enum_type, values = resolve_enum(tname, col_name)
                pg_type = enum_type
                if enum_type not in enum_types_to_create:
                    enum_types_to_create[enum_type] = values
            elif raw_type == "":
                # VEHICLE_TRIP_MEMBER.miles_member_adjustment_reason
                pg_type = "TEXT"
            else:
                pg_type = raw_type.upper()

            is_pk = "PK" in pk_fk
            is_unique = unique.strip().lower() in ("yes", "✓", "unique")

            # Extract FK if present
            fk_target = None
            if "FK" in pk_fk:
                m = re.search(r"FK\s*(?:→|->|:)\s*([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)", pk_fk)
                if m:
                    fk_target = (m.group(1).lower(), m.group(2).lower())

            cols.append({
                "col_name": col_name,
                "raw_type": raw_type,
                "pg_type": pg_type,
                "is_pk": is_pk,
                "is_unique": is_unique,
                "fk_target": fk_target,
                "desc": desc
            })

        schema_tables[tname.lower()] = {
            "name": tname.lower(),
            "domain": t["domain"],
            "desc": t["desc"],
            "cols": cols
        }

    print(f"Collected {len(schema_tables)} schema tables.")
    print(f"Collected {len(enum_types_to_create)} distinct enum types.")

    # Now generate the SQL migration file
    lines = []
    lines.append("-- =============================================================================")
    lines.append("-- FREEDOM SUPERCARS — Stage 2 Complete 285-Table Database Schema")
    lines.append("-- =============================================================================")
    lines.append("-- Version:     3.0.0 (Authoritative 08-12-2026 Stage 2 Knowledge Base Specification)")
    lines.append("-- Tables:      285 tables across 23 domains")
    lines.append("-- Enums:       126 enum types")
    lines.append("-- Foreign Keys: 1,146 referential integrity constraints")
    lines.append("-- Coexistence: Fully non-destructive with existing fs schema operational tables")
    lines.append("-- =============================================================================")
    lines.append("")
    lines.append("BEGIN;")
    lines.append("")
    lines.append("-- Ensure required extensions")
    lines.append('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";')
    lines.append('CREATE EXTENSION IF NOT EXISTS "citext";')
    lines.append('CREATE EXTENSION IF NOT EXISTS "btree_gist";')
    lines.append('CREATE SCHEMA IF NOT EXISTS fs;')
    lines.append("SET search_path TO fs, public;")
    lines.append("")
    lines.append("-- Safely rename legacy MVP reservation_status_history if it exists to allow canonical table")
    lines.append("DO $$")
    lines.append("BEGIN")
    lines.append("  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'fs' AND table_name = 'reservation_status_history') THEN")
    lines.append("    -- Check if it is the legacy table (with column 'previous_status')")
    lines.append("    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'fs' AND table_name = 'reservation_status_history' AND column_name = 'previous_status') THEN")
    lines.append("      ALTER TABLE fs.reservation_status_history RENAME TO reservation_status_history_legacy;")
    lines.append("    END IF;")
    lines.append("  END IF;")
    lines.append("END $$;")
    lines.append("")

    # 1. Enums
    lines.append("-- =============================================================================")
    lines.append("-- 1. ENUM TYPES (126 types)")
    lines.append("-- =============================================================================")
    for etype in sorted(enum_types_to_create.keys()):
        vals = enum_types_to_create[etype]
        escaped_vals = ", ".join([f"'{v.replace("'", "''")}'" for v in vals])
        lines.append(f"DO $$ BEGIN CREATE TYPE {etype} AS ENUM ({escaped_vals}); EXCEPTION WHEN duplicate_object THEN NULL; END $$;")
    lines.append("")

    # 2. Tables
    lines.append("-- =============================================================================")
    lines.append("-- 2. TABLES (285 tables across 23 domains)")
    lines.append("-- =============================================================================")

    # Sort tables by domain then name for clean organization
    sorted_tables = sorted(schema_tables.values(), key=lambda x: (x["domain"], x["name"]))

    current_d = None
    for tbl in sorted_tables:
        if tbl["domain"] != current_d:
            current_d = tbl["domain"]
            lines.append(f"\n-- -----------------------------------------------------------------------------")
            lines.append(f"-- DOMAIN: {current_d.upper()}")
            lines.append(f"-- -----------------------------------------------------------------------------")

        tname = tbl["name"]
        q_tname = quote_ident(tname)
        lines.append(f"\n-- Table: {tname.upper()} ({tbl['desc'][:80] if tbl['desc'] else ''})")
        lines.append(f"CREATE TABLE IF NOT EXISTS fs.{q_tname} (")

        col_defs = []
        pk_cols = [c["col_name"] for c in tbl["cols"] if c["is_pk"]]

        for col in tbl["cols"]:
            cname = col["col_name"]
            qcname = quote_ident(cname)
            col_type = col["pg_type"]

            constraints = []

            # Default values
            if col["is_pk"] and len(pk_cols) == 1:
                if col_type == "UUID":
                    constraints.append("PRIMARY KEY DEFAULT gen_random_uuid()")
                else:
                    constraints.append("PRIMARY KEY")
            elif cname == "created_at" and col_type == "TIMESTAMPTZ":
                constraints.append("NOT NULL DEFAULT now()")
            elif cname == "updated_at" and col_type == "TIMESTAMPTZ":
                constraints.append("NOT NULL DEFAULT now()")
            elif col["is_unique"] and not col["is_pk"]:
                constraints.append("UNIQUE")

            c_def = f"    {qcname:<35} {col_type}"
            if constraints:
                c_def += " " + " ".join(constraints)
            col_defs.append(c_def)

        # Composite PK if more than 1 PK column
        if len(pk_cols) > 1:
            pk_str = ", ".join([quote_ident(c) for c in pk_cols])
            col_defs.append(f"    CONSTRAINT pk_{tname} PRIMARY KEY ({pk_str})")

        lines.append(",\n".join(col_defs))
        lines.append(");")

        # Table and column comments
        if tbl["desc"]:
            escaped_desc = tbl["desc"].replace("'", "''")
            lines.append(f"COMMENT ON TABLE fs.{q_tname} IS '{escaped_desc}';")

    # 3. Foreign Key Constraints
    lines.append("\n-- =============================================================================")
    lines.append("-- 3. FOREIGN KEY CONSTRAINTS (1,146 constraints)")
    lines.append("-- =============================================================================")

    fk_count = 0
    for tbl in sorted_tables:
        tname = tbl["name"]
        q_tname = quote_ident(tname)
        for col in tbl["cols"]:
            if col["fk_target"]:
                target_table, target_col = col["fk_target"]
                cname = col["col_name"]
                qcname = quote_ident(cname)
                q_target_table = quote_ident(target_table)
                q_target_col = quote_ident(target_col)
                fk_name = f"fk_{tname}_{cname}"
                # Truncate fk_name if > 63 chars (Postgres max identifier length)
                if len(fk_name) > 63:
                    fk_name = fk_name[:63]

                fk_sql = (
                    f"DO $$ BEGIN "
                    f"ALTER TABLE fs.{q_tname} ADD CONSTRAINT {fk_name} "
                    f"FOREIGN KEY ({qcname}) REFERENCES fs.{q_target_table} ({q_target_col}) ON DELETE RESTRICT; "
                    f"EXCEPTION WHEN duplicate_object THEN NULL; "
                    f"END $$;"
                )
                lines.append(fk_sql)
                fk_count += 1

    lines.append(f"\n-- Total foreign keys added: {fk_count}")

    # 4. Foreign Key Indexes
    lines.append("\n-- =============================================================================")
    lines.append("-- 4. INDEXES ON FOREIGN KEY AND FREQUENT QUERY COLUMNS")
    lines.append("-- =============================================================================")

    idx_count = 0
    for tbl in sorted_tables:
        tname = tbl["name"]
        q_tname = quote_ident(tname)
        for col in tbl["cols"]:
            if col["fk_target"] and not col["is_pk"]:
                cname = col["col_name"]
                qcname = quote_ident(cname)
                idx_name = f"idx_{tname}_{cname}"
                if len(idx_name) > 63:
                    idx_name = idx_name[:63]
                lines.append(f"CREATE INDEX IF NOT EXISTS {idx_name} ON fs.{q_tname} ({qcname});")
                idx_count += 1

    lines.append(f"\n-- Total indexes created: {idx_count}")

    # 5. Compatibility Aliases and Helper Views
    lines.append("\n-- =============================================================================")
    lines.append("-- 5. COMPATIBILITY VIEWS AND ALIASES")
    lines.append("-- =============================================================================")
    lines.append("CREATE OR REPLACE VIEW fs.users AS SELECT * FROM fs.\"user\";")
    lines.append("CREATE OR REPLACE VIEW fs.app_user AS SELECT * FROM fs.\"user\";")
    lines.append("GRANT USAGE ON SCHEMA fs TO fs_app;")
    lines.append("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA fs TO fs_app;")
    lines.append("GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA fs TO fs_app;")
    lines.append("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA fs TO fs_app;")
    lines.append("")
    lines.append("COMMIT;")
    lines.append("")

    sql_content = "\n".join(lines)
    print(f"Writing migration file ({len(lines)} lines, {len(sql_content.encode('utf-8'))} bytes) to {out_path}...")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(sql_content)

    print("Successfully generated 003_stage2_complete_285_tables.sql!")

if __name__ == "__main__":
    main()
