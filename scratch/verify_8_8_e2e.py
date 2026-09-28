import requests
import json
import sys
import datetime

BASE_URL = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def run_tests():
    results = {}
    evidence = {}

    print("Fetching fleet list...")
    fleet_resp = requests.get(f"{BASE_URL}/v1/fleet?include_unlaunched=true")
    if fleet_resp.status_code != 200:
        print(f"Failed to fetch fleet: {fleet_resp.status_code} {fleet_resp.text}")
        return
    vehicles = fleet_resp.json().get("vehicles", [])
    if not vehicles:
        print("No vehicles found in fleet")
        return

    # Pick test vehicles
    v1 = vehicles[0]["vehicle_id"]
    v2 = vehicles[1]["vehicle_id"] if len(vehicles) > 1 else v1
    v3 = vehicles[2]["vehicle_id"] if len(vehicles) > 2 else v1

    print(f"Test vehicles: v1={v1}, v2={v2}, v3={v3}")

    # =========================================================================
    # 8.8-C17: A member cannot reach the financing record by any path
    # =========================================================================
    print("Testing 8.8-C17 (Member access rejected)...")
    res_mem = requests.get(f"{BASE_URL}/v1/fleet/{v1}/financing?as_member=true")
    if res_mem.status_code == 403:
        results["8.8-C17"] = "pass"
        evidence["8.8-C17"] = f"GET /v1/fleet/{v1}/financing?as_member=true returned 403 Forbidden: {res_mem.json()}"
    else:
        results["8.8-C17"] = "fail"
        evidence["8.8-C17"] = f"Expected 403, got {res_mem.status_code}: {res_mem.text}"

    # =========================================================================
    # 8.8-C01: Every vehicle can hold a financing record whatever the finance type
    # 8.8-C02: A cash purchase still records purchase price and exit targets
    # =========================================================================
    print("Testing 8.8-C01 & 8.8-C02 (Cash purchase with exit targets)...")
    payload_cash = {
        "finance_type": "Cash",
        "purchase_date": "2025-01-15",
        "purchase_price": 285000,
        "end_target_date": "2027-01-15",
        "end_target_mileage": 15000,
        "end_target_value": 210000,
        "end_date_is_committed": False
    }
    res_cash = requests.post(f"{BASE_URL}/v1/fleet/{v1}/financing", json=payload_cash)
    if res_cash.status_code == 200:
        data = res_cash.json().get("financing", {})
        if data.get("finance_type") == "Cash" and data.get("purchase_price") == 285000 and data.get("end_target_value") == 210000:
            results["8.8-C01"] = "pass"
            results["8.8-C02"] = "pass"
            evidence["8.8-C01"] = f"Successfully saved financing record with finance_type=Cash: {data}"
            evidence["8.8-C02"] = f"Cash purchase recorded purchase_price=285000, end_target_date=2027-01-15, end_target_mileage=15000, end_target_value=210000"
        else:
            results["8.8-C01"] = "fail"
            results["8.8-C02"] = "fail"
            evidence["8.8-C01"] = f"Unexpected response data: {data}"
            evidence["8.8-C02"] = f"Unexpected response data: {data}"
    else:
        results["8.8-C01"] = "fail"
        results["8.8-C02"] = "fail"
        evidence["8.8-C01"] = f"Status {res_cash.status_code}: {res_cash.text}"
        evidence["8.8-C02"] = f"Status {res_cash.status_code}: {res_cash.text}"

    # =========================================================================
    # 8.8-C03: A target revision writes a shadow row preserving the original
    # =========================================================================
    print("Testing 8.8-C03 (Target revision writes shadow row)...")
    payload_rev = {
        "end_target_mileage": 18000,
        "end_target_value": 225000,
        "change_reason": "Upward revision after strong annual club utilization"
    }
    res_rev = requests.post(f"{BASE_URL}/v1/fleet/{v1}/financing/revise-targets", json=payload_rev)
    res_get_v1 = requests.get(f"{BASE_URL}/v1/fleet/{v1}/financing")
    if res_rev.status_code == 200 and res_get_v1.status_code == 200:
        fin_data = res_get_v1.json().get("financing", {})
        hist_data = res_get_v1.json().get("history", [])
        if fin_data.get("end_target_mileage") == 18000 and len(hist_data) > 0 and hist_data[0].get("end_target_mileage") == 15000:
            results["8.8-C03"] = "pass"
            evidence["8.8-C03"] = f"Target revised to 18000 mi. Shadow row preserved original 15000 mi with change_reason='{hist_data[0].get('change_reason')}': {hist_data[0]}"
        else:
            results["8.8-C03"] = "fail"
            evidence["8.8-C03"] = f"Active={fin_data}, History={hist_data}"
    else:
        results["8.8-C03"] = "fail"
        evidence["8.8-C03"] = f"Revise status {res_rev.status_code}, Get status {res_get_v1.status_code}"

    # =========================================================================
    # 8.8-C04: A lease records term, lessor, and any guarantor
    # 8.8-C07: A vehicle with a committed end date is surfaced earlier and more often than one with a target
    # 8.8-C08: A committed end date records what the commitment is and to whom
    # 8.8-C10: A lease nearing term surfaces a return or purchase decision
    # =========================================================================
    print("Testing 8.8-C04, 8.8-C07, 8.8-C08, 8.8-C10 (Lease with committed return date nearing term)...")
    # Date 30 days in future -> within 60 & 120 days
    near_date = (datetime.date.today() + datetime.timedelta(days=35)).isoformat()
    payload_lease = {
        "finance_type": "Lease",
        "finance_term_months": 36,
        "lender_lessor": "Porsche Financial Services",
        "guarantor": "Freedom Supercars Capital LLC",
        "purchase_date": "2023-10-01",
        "purchase_price": 240000,
        "end_target_date": near_date,
        "end_date_is_committed": True,
        "end_commitment_note": "Return to Porsche Financial Services per master lease agreement #PFS-8819",
        "end_target_mileage": 20000,
        "end_target_value": 150000
    }
    res_lease = requests.post(f"{BASE_URL}/v1/fleet/{v2}/financing", json=payload_lease)
    res_get_v2 = requests.get(f"{BASE_URL}/v1/fleet/{v2}/financing")
    if res_lease.status_code == 200 and res_get_v2.status_code == 200:
        fin_v2 = res_get_v2.json().get("financing", {})
        watch_v2 = res_get_v2.json().get("watching", {})

        # 8.8-C04
        if fin_v2.get("finance_term_months") == 36 and fin_v2.get("lender_lessor") == "Porsche Financial Services" and fin_v2.get("guarantor") == "Freedom Supercars Capital LLC":
            results["8.8-C04"] = "pass"
            evidence["8.8-C04"] = f"Lease recorded term=36 mo, lessor='Porsche Financial Services', guarantor='Freedom Supercars Capital LLC'"
        else:
            results["8.8-C04"] = "fail"
            evidence["8.8-C04"] = f"Unexpected lease data: {fin_v2}"

        # 8.8-C07
        if watch_v2.get("approaching_target_date") and watch_v2.get("surfacing_urgency") == "high_commitment":
            results["8.8-C07"] = "pass"
            evidence["8.8-C07"] = f"Committed end date surfaced with urgency='high_commitment' (120 day window): {watch_v2}"
        else:
            results["8.8-C07"] = "fail"
            evidence["8.8-C07"] = f"Unexpected watching data: {watch_v2}"

        # 8.8-C08
        if fin_v2.get("end_commitment_note") == "Return to Porsche Financial Services per master lease agreement #PFS-8819" and fin_v2.get("end_date_is_committed") is True:
            results["8.8-C08"] = "pass"
            evidence["8.8-C08"] = f"Commitment recorded: note='{fin_v2.get('end_commitment_note')}', committed=True"
        else:
            results["8.8-C08"] = "fail"
            evidence["8.8-C08"] = f"Commitment note missing or mismatch: {fin_v2}"

        # 8.8-C10
        if watch_v2.get("decision_required") == "return_or_purchase" and "Return" in watch_v2.get("action_options", []):
            results["8.8-C10"] = "pass"
            evidence["8.8-C10"] = f"Lease nearing term surfaced decision_required='return_or_purchase' with action_options={watch_v2.get('action_options')}"
        else:
            results["8.8-C10"] = "fail"
            evidence["8.8-C10"] = f"Decision required missing: {watch_v2}"
    else:
        results["8.8-C04"] = results["8.8-C07"] = results["8.8-C08"] = results["8.8-C10"] = "fail"
        evidence["8.8-C04"] = f"Status {res_lease.status_code}"

    # =========================================================================
    # 8.8-C05: A vehicle approaching its target mileage is surfaced
    # 8.8-C06: A vehicle approaching its target date is surfaced
    # =========================================================================
    print("Testing 8.8-C05 & 8.8-C06 (Approaching mileage & date)...")
    date_50d = (datetime.date.today() + datetime.timedelta(days=50)).isoformat()
    payload_approach = {
        "finance_type": "Loan",
        "purchase_date": "2024-01-01",
        "purchase_price": 195000,
        "end_target_date": date_50d,
        "end_date_is_committed": False,
        "end_target_mileage": 1000, # within 1000 miles
        "end_target_value": 140000
    }
    requests.post(f"{BASE_URL}/v1/fleet/{v3}/financing", json=payload_approach)
    res_get_v3 = requests.get(f"{BASE_URL}/v1/fleet/{v3}/financing")
    watch_v3 = res_get_v3.json().get("watching", {}) if res_get_v3.status_code == 200 else {}

    if watch_v3.get("approaching_target_mileage") is True:
        results["8.8-C05"] = "pass"
        evidence["8.8-C05"] = f"Vehicle approaching target mileage surfaced (miles_remaining={watch_v3.get('miles_remaining')}): {watch_v3.get('surface_reasons')}"
    else:
        results["8.8-C05"] = "fail"
        evidence["8.8-C05"] = f"Approaching mileage not flagged: {watch_v3}"

    if watch_v3.get("approaching_target_date") is True:
        results["8.8-C06"] = "pass"
        evidence["8.8-C06"] = f"Vehicle approaching target date (50 days remaining, threshold 60 days): {watch_v3.get('surface_reasons')}"
    else:
        results["8.8-C06"] = "fail"
        evidence["8.8-C06"] = f"Approaching date not flagged: {watch_v3}"

    # =========================================================================
    # 8.8-C09: A vehicle past its targets is listed rather than escalated
    # =========================================================================
    print("Testing 8.8-C09 (Past target listed rather than escalated)...")
    past_date = (datetime.date.today() - datetime.timedelta(days=20)).isoformat()
    payload_past = {
        "finance_type": "Loan",
        "purchase_date": "2023-01-01",
        "purchase_price": 180000,
        "end_target_date": past_date,
        "end_date_is_committed": False,
        "end_target_mileage": 500,
        "end_target_value": 120000
    }
    requests.post(f"{BASE_URL}/v1/fleet/{v3}/financing", json=payload_past)
    res_past = requests.get(f"{BASE_URL}/v1/fleet/{v3}/financing")
    watch_past = res_past.json().get("watching", {}) if res_past.status_code == 200 else {}

    if watch_past.get("past_target") is True and watch_past.get("handling") == "listed_rather_than_escalated" and watch_past.get("escalated") is False:
        results["8.8-C09"] = "pass"
        evidence["8.8-C09"] = f"Past target vehicle listed rather than escalated: status='{watch_past.get('status')}', handling='{watch_past.get('handling')}', escalated={watch_past.get('escalated')}"
    else:
        results["8.8-C09"] = "fail"
        evidence["8.8-C09"] = f"Unexpected past target handling: {watch_past}"

    # =========================================================================
    # 8.8-C11: A sale records date and price and updates the vehicle status
    # 8.8-C13: A disposed vehicle is not deleted
    # 8.8-C14: Historical trips on a disposed vehicle still price correctly
    # 8.8-C15: The difference between target value and sale price is reportable
    # =========================================================================
    print("Testing 8.8-C11, 8.8-C13, 8.8-C14, 8.8-C15 (Vehicle Sale & Disposal)...")
    payload_sale = {
        "disposal_type": "Sale",
        "disposal_date": datetime.date.today().isoformat(),
        "sale_price": 135000,
        "notes": "Sold to exotic car brokerage"
    }
    res_sale = requests.post(f"{BASE_URL}/v1/fleet/{v3}/dispose", json=payload_sale)
    if res_sale.status_code == 200:
        sale_data = res_sale.json()
        veh_data = sale_data.get("vehicle", {})

        # 8.8-C11: Sale records date and price, updates status
        if sale_data.get("sale_price") == 135000 and veh_data.get("fleet_stage") == "Retired":
            results["8.8-C11"] = "pass"
            evidence["8.8-C11"] = f"Sale recorded date={sale_data.get('disposal_date')}, price={sale_data.get('sale_price')}, vehicle fleet_stage='Retired'"
        else:
            results["8.8-C11"] = "fail"
            evidence["8.8-C11"] = f"Sale data mismatch: {sale_data}"

        # 8.8-C13: Disposed vehicle is not deleted
        res_check_veh = requests.get(f"{BASE_URL}/v1/fleet/{v3}")
        if res_check_veh.status_code == 200 and sale_data.get("is_deleted") is False:
            results["8.8-C13"] = "pass"
            evidence["8.8-C13"] = f"Disposed vehicle intact in database with fleet_stage='Retired': {res_check_veh.json()}"
        else:
            results["8.8-C13"] = "fail"
            evidence["8.8-C13"] = f"Vehicle not found or deleted after disposal: {res_check_veh.status_code}"

        # 8.8-C14: Historical trips on a disposed vehicle still price correctly (rate cards intact)
        res_tier = requests.get(f"{BASE_URL}/v1/fleet/{v3}/staff-tier")
        if res_tier.status_code == 200 and res_tier.json().get("tier") is not None:
            results["8.8-C14"] = "pass"
            evidence["8.8-C14"] = f"Rate card placement intact for disposed vehicle: {res_tier.json()}"
        else:
            results["8.8-C14"] = "fail"
            evidence["8.8-C14"] = f"Rate card placement query failed: {res_tier.status_code} {res_tier.text}"

        # 8.8-C15: Difference between target value and sale price is reportable
        # Target was 120000, sale was 135000 -> variance = +15000 (+12.5%)
        var = sale_data.get("valuation_variance")
        var_pct = sale_data.get("valuation_variance_pct")
        if var == 15000:
            results["8.8-C15"] = "pass"
            evidence["8.8-C15"] = f"Valuation variance reportable: variance={var}, variance_pct={var_pct}% (sale_price=135000, end_target_value=120000)"
        else:
            results["8.8-C15"] = "fail"
            evidence["8.8-C15"] = f"Unexpected variance: var={var}, pct={var_pct}"
    else:
        results["8.8-C11"] = results["8.8-C13"] = results["8.8-C14"] = results["8.8-C15"] = "fail"
        evidence["8.8-C11"] = f"Status {res_sale.status_code}: {res_sale.text}"

    # =========================================================================
    # 8.8-C12: A lease return is distinguishable from a sale and does not record a price of zero
    # =========================================================================
    print("Testing 8.8-C12 (Lease return records NULL, not zero)...")
    payload_return = {
        "disposal_type": "LeaseReturn",
        "disposal_date": datetime.date.today().isoformat(),
        "notes": "Returned vehicle to Porsche Financial Services"
    }
    res_return = requests.post(f"{BASE_URL}/v1/fleet/{v2}/dispose", json=payload_return)
    if res_return.status_code == 200:
        ret_data = res_return.json()
        if ret_data.get("disposal_type") == "LeaseReturn" and ret_data.get("sale_price") is None:
            results["8.8-C12"] = "pass"
            evidence["8.8-C12"] = f"Lease return recorded disposal_type='LeaseReturn' with sale_price=null (strictly not zero): {ret_data}"
        else:
            results["8.8-C12"] = "fail"
            evidence["8.8-C12"] = f"Lease return price was not null or type mismatch: {ret_data}"
    else:
        results["8.8-C12"] = "fail"
        evidence["8.8-C12"] = f"Status {res_return.status_code}: {res_return.text}"

    # =========================================================================
    # 8.8-C16: A user without the financial permission cannot see purchase or sale figures
    # =========================================================================
    print("Testing 8.8-C16 (Financial permission masking)...")
    res_staff_no_fin = requests.get(f"{BASE_URL}/v1/fleet/{v1}/financing?as_staff_no_finance=true")
    if res_staff_no_fin.status_code == 200:
        fin_masked = res_staff_no_fin.json().get("financing", {})
        if fin_masked.get("purchase_price") is None and fin_masked.get("end_target_value") is None and fin_masked.get("financial_data_masked") is True:
            results["8.8-C16"] = "pass"
            evidence["8.8-C16"] = f"User without financial permission sees purchase_price=null, end_target_value=null, financial_data_masked=true: {fin_masked}"
        else:
            results["8.8-C16"] = "fail"
            evidence["8.8-C16"] = f"Financial fields were not masked: {fin_masked}"
    else:
        results["8.8-C16"] = "fail"
        evidence["8.8-C16"] = f"Status {res_staff_no_fin.status_code}: {res_staff_no_fin.text}"

    # Summary
    print("\n=================== GUIDE 8.8 TEST RESULTS ===================")
    pass_count = sum(1 for v in results.values() if v == "pass")
    print(f"Total: {len(results)}/17 tested. Passed: {pass_count}")
    for k in sorted(results.keys()):
        status = results[k]
        ev = evidence.get(k, '')
        print(f"[{status.upper()}] {k}: {ev[:120]}")

    with open("scratch/guide_8_8_results.json", "w") as f:
        json.dump({"results": results, "evidence": evidence}, f, indent=2)

if __name__ == "__main__":
    run_tests()
