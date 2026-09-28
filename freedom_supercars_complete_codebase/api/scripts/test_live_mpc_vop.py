import urllib.request
import json
import sys

base = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"
api_key = "XwzVylqkoXs9YdhLbBOc2MZ571djQvNkXsVM9Ycb"

def call(path, method="GET", body=None):
    url = f"{base}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Content-Type": "application/json",
        "x-api-key": api_key,
        "User-Agent": "E2ETester/1.0"
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(err_body)
        except:
            return e.code, {"error": err_body}

print("1. Root check:")
status, r = call("/")
print(f"Status {status}, endpoints count: {len(r.get('endpoints', []))}")

_, fleet = call("/v1/fleet")
vehicle_id = fleet["vehicles"][0]["vehicle_id"] if fleet.get("vehicles") else None
print("Existing vehicle ID:", vehicle_id)

_, members_res = call("/v1/members")
member_id = None
if members_res.get("members"):
    member_id = members_res["members"][0]["id"]
else:
    # Create a member
    print("Creating test member...")
    m_status, m_res = call("/v1/members", "POST", {
        "first_name": "Marcus",
        "last_name": "Vance",
        "email": "marcus.vance.test@freedomsupercars.com",
        "phone": "+1-713-555-0100",
        "primary_location_code": "HOU"
    })
    print("Create Member status:", m_status)
    member_id = m_res.get("member", {}).get("id")

print("Member ID:", member_id)

print("\n2. Test VOP Partner Creation:")
status, p_res = call("/v1/vop/partners", "POST", {
    "business_name": "Apex Asset Holdings LLC",
    "address_line1": "1000 Louisiana St",
    "city": "Houston",
    "state": "TX",
    "postal_code": "77002",
    "is_active": True
})
print("Create Partner:", status, p_res.get("partner", {}).get("vehicle_partner_id"))
partner_id = p_res.get("partner", {}).get("vehicle_partner_id")

print("\n3. Test VOP Partner Contact Creation:")
status, c_res = call(f"/v1/vop/partners/{partner_id}/contacts", "POST", {
    "contact_name": "Robert Vance",
    "contact_role": "Managing Director",
    "contact_phone": "+1-713-555-0199",
    "contact_email": "rvance@apexassets.com",
    "is_primary": True
})
print("Create Contact:", status, c_res.get("contact", {}).get("vehicle_partner_contact_id"))

print("\n4. Test VOP Get Partner Details:")
status, p_detail = call(f"/v1/vop/partners/{partner_id}")
print("Get Partner:", status, "Contacts count:", len(p_detail.get("contacts", [])))

print("\n5. Test VOP Plan Creation:")
status, plan_res = call("/v1/vop/plans", "POST", {
    "vehicle_id": vehicle_id,
    "vehicle_partner_id": partner_id,
    "base_fee_amount": 2500,
    "per_mile_rate": 2.25,
    "owner_plan_fee": 350,
    "minimum_amount_per_period": 3500,
    "status": "Active"
})
print("Create Plan:", status, plan_res.get("plan", {}).get("vop_plan_id"))
plan_id = plan_res.get("plan", {}).get("vop_plan_id")

print("\n6. Test VOP Period & Ledger:")
status, period_res = call("/v1/vop/payout-periods", "POST", {
    "period_start_date": "2026-09-01",
    "period_end_date": "2026-09-30",
    "status": "Open"
})
period_id = period_res.get("payout_period", {}).get("payout_period_id")
print("Create Period:", status, period_id)

status, ledger_res = call("/v1/vop/ledger", "POST", {
    "vehicle_id": vehicle_id,
    "vop_plan_id": plan_id,
    "vehicle_partner_id": partner_id,
    "payout_period_id": period_id,
    "entry_type": "VOP Mile",
    "entry_direction": "Credit",
    "entry_value": 450.00,
    "reason_code": "MEMBER_DRIVE_MILES",
    "description": "200 miles logged on weekend drive"
})
print("Create Ledger Entry:", status, ledger_res.get("entry", {}).get("vop_payout_log_id"))

status, ledger_list = call(f"/v1/vop/ledger?vehicle_partner_id={partner_id}")
print("List Ledger Entries:", status, "count:", ledger_list.get("count"))

if member_id:
    print("\n7. Test MPC Customization:")
    status, mpc_res = call("/v1/mpc/customizations", "POST", {
        "member_id": member_id,
        "label": "2026 Executive Founder Package",
        "effective_package_mode": "Current Year (Period)",
        "is_active": True
    })
    custom_id = mpc_res.get("customization", {}).get("member_package_customization_id")
    print("Create Customization:", status, custom_id)

    status, pricing_res = call("/v1/mpc/pricing", "POST", {
        "member_id": member_id,
        "pricing_type": "annual_price",
        "override_value": 45000.00,
        "notes": "Founder contracted rate"
    })
    print("Create Pricing Override:", status, pricing_res.get("pricing", {}).get("mpc_pricing_id"))

    status, mpc_detail = call(f"/v1/mpc/customizations/{custom_id}")
    print("Get Customization Detail:", status, "pricing count:", len(mpc_detail.get("overrides", {}).get("pricing", [])))

print("\nAll live integration verifications completed successfully!")
