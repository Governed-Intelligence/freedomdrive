import subprocess
import json
import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

results = {}

def run_gcloud(args):
    cmd = ["gcloud"] + args
    res = subprocess.run(cmd, capture_output=True, text=True, shell=True)
    if res.returncode != 0:
        return {"error": res.stderr.strip()}
    try:
        return json.loads(res.stdout)
    except:
        return res.stdout.strip()

print("--- 1. Project Info ---")
proj = run_gcloud(["projects", "describe", "freedom-supercars-prod", "--format=json"])
print(json.dumps({
    "projectId": proj.get("projectId"),
    "projectNumber": proj.get("projectNumber"),
    "lifecycleState": proj.get("lifecycleState")
}, indent=2))

print("\n--- 2. Billing Info ---")
billing = run_gcloud(["billing", "projects", "describe", "freedom-supercars-prod", "--format=json"])
print(json.dumps(billing, indent=2))

print("\n--- 3. Cloud SQL Instance ---")
sql_inst = run_gcloud(["sql", "instances", "describe", "freedom-supercars-prod-pg-6792", "--format=json"])
if "error" not in sql_inst:
    settings = sql_inst.get("settings", {})
    ip_config = settings.get("ipConfiguration", {})
    backup_config = settings.get("backupConfiguration", {})
    print(json.dumps({
        "name": sql_inst.get("name"),
        "databaseVersion": sql_inst.get("databaseVersion"),
        "tier": settings.get("tier"),
        "ipv4_enabled": ip_config.get("ipv4Enabled"),
        "private_network": ip_config.get("privateNetwork"),
        "ssl_mode": ip_config.get("sslMode"),
        "pitr": backup_config.get("pointInTimeRecoveryEnabled"),
        "deletion_protection": settings.get("deletionProtectionEnabled")
    }, indent=2))
else:
    print(sql_inst)

print("\n--- 4. Cloud Run Services ---")
run_services = run_gcloud(["run", "services", "list", "--region=us-south1", "--format=json"])
if isinstance(run_services, list):
    for svc in run_services:
        print(f"Service: {svc.get('metadata', {}).get('name')}")
        print(f"  URL: {svc.get('status', {}).get('url')}")
        print(f"  Latest Revision: {svc.get('status', {}).get('latestReadyRevisionName')}")

print("\n--- 5. VPC and Connector ---")
connector = run_gcloud(["compute", "networks", "vpc-access", "connectors", "describe", "freedom-supercar-vpcconn", "--region=us-south1", "--format=json"])
if "error" not in connector:
    print(json.dumps({
        "name": connector.get("name"),
        "network": connector.get("network"),
        "ipCidrRange": connector.get("ipCidrRange"),
        "minInstances": connector.get("minInstances"),
        "maxInstances": connector.get("maxInstances"),
        "machineType": connector.get("machineType"),
        "state": connector.get("state")
    }, indent=2))
else:
    print(connector)

print("\n--- 6. Secret Manager Secrets ---")
secrets = run_gcloud(["secrets", "list", "--format=json"])
if isinstance(secrets, list):
    for s in secrets:
        print(f"Secret: {s.get('name', '').split('/')[-1]}")

print("\n--- 7. Cloud Run Job Migrations ---")
job_execs = run_gcloud(["run", "jobs", "executions", "list", "--job=freedom-supercars-prod-migrate", "--region=us-south1", "--limit=5", "--format=json"])
if isinstance(job_execs, list):
    for ex in job_execs:
        meta = ex.get("metadata", {})
        status = ex.get("status", {})
        print(f"Execution: {meta.get('name')} | Completion: {status.get('completionTime')}")

print("\n--- 8. Live HTTP Endpoints Check ---")
endpoints = [
    "https://freedom-supercars-prod-api-721852694030.us-south1.run.app/",
    "https://freedom-supercars-prod-api-721852694030.us-south1.run.app/v1/tiers",
    "https://freedom-supercars-prod-api-721852694030.us-south1.run.app/v1/fleet",
    "https://freedom-supercars-web-s4egn2gcka-vp.a.run.app"
]
for url in endpoints:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            body = resp.read().decode('utf-8', errors='ignore')
            print(f"URL: {url} -> Status {resp.status}, Body length: {len(body)}")
            if "tiers" in url or url.endswith("/"):
                try:
                    parsed = json.loads(body)
                    print("  Preview:", str(parsed)[:160])
                except:
                    pass
            elif "fleet" in url:
                try:
                    parsed = json.loads(body)
                    if isinstance(parsed, dict) and "fleet" in parsed:
                        print(f"  Fleet count: {len(parsed['fleet'])}")
                    elif isinstance(parsed, list):
                        print(f"  Fleet count: {len(parsed)}")
                except:
                    pass
    except Exception as e:
        print(f"URL: {url} -> Error: {e}")
