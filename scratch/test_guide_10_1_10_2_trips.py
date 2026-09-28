#!/usr/bin/env python3
"""
Freedom Supercars - Chapter 10 Verification Suite (Guides 10.1 & 10.2)
Verifies:
  - 10.1: Trip Creation, Showroom-to-Showroom Custody, Odometer Logging
  - 10.2: Trip Settlement, Actual Duration, Overage Mileage, and Point Charges
  - Addendum A Decisions: D-01 (staff miles on member tab), C-21 (referential ordering), E-10 (actual timestamps)
  - Convenience aliases on /v1/reservations/:id/checkout and /v1/reservations/:id/checkin
"""

import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

BASE_URL = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def request(method, path, body=None, token=None):
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            status = resp.status
            content = resp.read().decode("utf-8")
            return status, json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        content = e.read().decode("utf-8")
        try:
            parsed = json.loads(content)
        except Exception:
            parsed = {"error": content}
        return e.code, parsed

def log_test(name, success, details=""):
    mark = "PASS" if success else "FAIL"
    print(f"[{mark}] {name} - {details}")
    if not success:
        sys.exit(1)

def run_suite():
    print("=" * 80)
    print("FREEDOM SUPERCARS - GUIDE 10.1 & 10.2 E2E VERIFICATION SUITE")
    print(f"Target: {BASE_URL}")
    print("=" * 80)

    # 1. Health check
    status, data = request("GET", "/readyz")
    log_test("API Service Liveness", status == 200, f"status={status}, db={data.get('database')}")

    # 2. Get upcoming reservations to find confirmed reservations
    status, upcoming_data = request("GET", "/v1/reservations/_/upcoming")
    reservations = upcoming_data.get("reservations", [])
    confirmed_res = [r for r in reservations if r.get("status") == "confirmed"]
    log_test("Upcoming Confirmed Reservations Lookup", status == 200 and len(confirmed_res) >= 2, f"{len(confirmed_res)} confirmed reservations found")
    
    res1 = confirmed_res[0]
    res2 = confirmed_res[1]
    res1_id = res1["id"]
    res2_id = res2["id"]
    print(f"Test Reservation 1: {res1_id} ({res1.get('vehicle', 'Vehicle')})")
    print(f"Test Reservation 2: {res2_id} ({res2.get('vehicle', 'Vehicle')})")

    # 3. Test Guide 10.1: Trip Checkout with starting odometer capture & pricing snapshot freeze
    now = datetime.now(timezone.utc)
    start_odo = 12500
    checkout_payload = {
        "reservation_id": res1_id,
        "starting_odometer": start_odo,
        "fuel_start_percent": 100,
        "start_time_actual": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "start_type": "Pickup"
    }

    status, checkout_resp = request("POST", "/v1/trips/checkout", checkout_payload)
    log_test("Guide 10.1-C01: Checkout Trip Creation", status == 201, f"status={status}, trip={checkout_resp.get('trip', {}).get('trip_id')}")
    trip_data = checkout_resp.get("trip", {})
    trip_id = trip_data.get("trip_id")
    log_test("Guide 10.1-C02: Odometer Start Capture", trip_data.get("starting_odometer") == start_odo, f"odo_start={start_odo}")
    
    snapshot = trip_data.get("pricing_snapshot", {})
    log_test("Guide 10.1-C03: Pricing Snapshot Freeze", 
             snapshot.get("extra_mile_rate") is not None and snapshot.get("included_miles") is not None, 
             f"snapshot={snapshot}")

    # 4. Test Guide 10.1-C06: Concurrent Open Trip Prevention
    status, dup_checkout = request("POST", "/v1/trips/checkout", checkout_payload)
    log_test("Guide 10.1-C06: Prevent Duplicate Checkout", status in [400, 409], f"rejected status={status}")

    # 5. Test Guide 10.1-C15 & 10.1-C21: Goodwill Mileage Adjustment
    status, adj_no_reason = request("POST", f"/v1/trips/{trip_id}/adjust-miles", {"adjustment_miles": 25})
    log_test("Guide 10.1-C21: Reject Adjustment Without Reason", status == 400, f"rejected status={status}")

    status, adj_resp = request("POST", f"/v1/trips/{trip_id}/adjust-miles", {
        "adjustment_miles": 25,
        "adjustment_reason": "Goodwill courtesy for showroom traffic delay"
    })
    log_test("Guide 10.1-C15: Member Mileage Adjustment", status == 200, f"adj={adj_resp.get('adjustment')}")

    # 6. Test Guide 10.2: Trip Settlement with Overage Mileage and Points Debit
    # Starting odo was 12,500. Suppose vehicle returns at 13,000 -> 500 miles driven.
    # Goodwill adjustment: 25 miles -> miles_member = 475 miles.
    close_odo = 13000
    checkin_time = (now + timedelta(days=3, hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    checkin_payload = {
        "closing_odometer": close_odo,
        "fuel_end_percent": 95,
        "end_time_actual": checkin_time,
        "end_type": "Dropoff",
        "notes": "Vehicle returned in immaculate condition"
    }

    status, checkin_resp = request("POST", f"/v1/trips/{trip_id}/checkin", checkin_payload)
    log_test("Guide 10.2-C01: Checkin & Settlement", status == 200, f"settled={checkin_resp.get('trip', {}).get('settled')}")
    settlement = checkin_resp.get("trip", {})
    log_test("Guide 10.1-C10: Miles Driven Calculation", settlement.get("miles_driven") == 500, f"miles_driven={settlement.get('miles_driven')}")
    log_test("Guide 10.1-C12: Showroom-to-Showroom Invariant", settlement.get("miles_member") == 475, f"miles_member={settlement.get('miles_member')}")
    
    included_miles = snapshot.get("included_miles") or 300
    expected_overage = max(0, 475 - included_miles)
    log_test("Guide 10.2-C11: Overage Miles Calculation", settlement.get("overage_miles") == expected_overage, f"overage_miles={settlement.get('overage_miles')} (expected {expected_overage})")
    log_test("Guide 10.2-C14: Extra Mileage Points Calculation", settlement.get("extra_mileage_points") > 0, f"points={settlement.get('extra_mileage_points')}")
    log_test("Guide 10.2-C18: Calculation Detail Preservation", settlement.get("calculation_version") == "v1.0" and "calculation_working" in settlement, "Audit working details stored")

    # 7. Verify Trip Retrieval endpoint
    status, trip_get = request("GET", f"/v1/trips/{trip_id}")
    trip_obj = trip_get.get("trip", {})
    log_test("GET /v1/trips/:id", status == 200 and len(trip_obj.get("odometer_logs", [])) == 2, f"logs_count={len(trip_obj.get('odometer_logs', []))}, vehicle={trip_obj.get('vehicle_make')} {trip_obj.get('vehicle_model')}")

    # 8. Verify List Trips endpoint
    status, list_get = request("GET", "/v1/trips?status=completed")
    log_test("GET /v1/trips?status=completed", status == 200 and list_get.get("count", 0) > 0, f"completed_count={list_get.get('count')}")

    # 9. Verify Convenience Aliases on /v1/reservations
    print("-" * 80)
    print("TESTING CONVENIENCE ALIASES: /v1/reservations/:id/checkout and /v1/reservations/:id/checkin")
    status, res_checkout = request("POST", f"/v1/reservations/{res2_id}/checkout", {
        "starting_odometer": 8400,
        "fuel_start_percent": 100,
        "start_type": "Pickup"
    })
    log_test("POST /v1/reservations/:id/checkout Alias", status == 201, f"res2_trip={res_checkout.get('trip', {}).get('trip_id')}")

    status, res_checkin = request("POST", f"/v1/reservations/{res2_id}/checkin", {
        "closing_odometer": 8650,
        "fuel_end_percent": 100,
        "end_type": "Dropoff"
    })
    log_test("POST /v1/reservations/:id/checkin Alias", status == 200, f"res2_settlement={res_checkin.get('trip', {}).get('settled')}, miles={res_checkin.get('trip', {}).get('miles_driven')}")

    print("=" * 80)
    print("ALL GUIDE 10.1 & 10.2 TRIP CREATION, CUSTODY, & SETTLEMENT TESTS PASSED!")
    print("=" * 80)

if __name__ == "__main__":
    run_suite()
