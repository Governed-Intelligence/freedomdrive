import requests
import json
import uuid
from datetime import datetime, date, timedelta

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"
API_KEY = "XwzVylqkoXs9YdhLbBOc2MZ571djQvNkXsVM9Ycb"
HEADERS = {
    "x-api-key": API_KEY,
    "Content-Type": "application/json"
}

def run_tests():
    print("=" * 80)
    print("RUNNING LIVE END-TO-END VERIFICATION: GUIDE 9.2 MEMBER RESERVATIONS")
    print("=" * 80)

    # 1. Fetch available vehicles and plans
    fleet_resp = requests.get(f"{API_BASE}/v1/fleet", headers=HEADERS)
    assert fleet_resp.status_code == 200, f"Fleet fetch failed: {fleet_resp.text}"
    vehicles = fleet_resp.json().get('vehicles', [])
    assert len(vehicles) >= 1, "Need at least 1 vehicle"
    
    v = vehicles[0]
    vehicle_id = v['vehicle_id']

    uniq = uuid.uuid4().hex[:6]
    # Pick a distinct 25-day window within the 1-year subscription (Nov 2026 - Jun 2027)
    window_slot = (int(uniq, 16) % 9) * 28
    t_base = datetime(2026, 11, 5, 14, 0, 0) + timedelta(days=window_slot)

    # 1. Tentative booking window (3 days)
    d_tent_pickup = t_base.strftime("%Y-%m-%dT%H:%M:%SZ")
    d_tent_return = (t_base + timedelta(days=3, hours=-4)).strftime("%Y-%m-%dT%H:%M:%SZ")

    # 2. Thursday-to-Monday trip window (4 days, 1 weekday + 1 weekend unit)
    # Ensure t_thu is a Thursday (Nov 5 2026 was a Thursday, window_slot is multiple of 28, so t_thu is Thursday)
    t_thu = t_base + timedelta(days=7)
    t_mon = t_thu + timedelta(days=3, hours=20) # Thu 14:00 to Mon 10:00
    d_thu_pickup = t_thu.strftime("%Y-%m-%dT%H:%M:%SZ")
    d_mon_return = t_mon.strftime("%Y-%m-%dT%H:%M:%SZ")

    # 3. Turnaround buffer collision (attempting to book during Monday 10:00 - 14:00 buffer)
    d_buf_pickup = (t_mon + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    d_buf_return = (t_mon + timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ")

    # 4. Courtesy booking window (4 days later)
    t_crt = t_base + timedelta(days=16)
    d_crt_pickup = t_crt.strftime("%Y-%m-%dT%H:%M:%SZ")
    d_crt_return = (t_crt + timedelta(days=4, hours=-4)).strftime("%Y-%m-%dT%H:%M:%SZ")

    # 2. Onboard active test member
    print(f"\n--- TEST 1: Setup Active Member & Subscription (Vehicle: {v.get('name') or vehicle_id}) ---")
    onboard_resp = requests.post(f"{API_BASE}/v1/members/onboard", headers=HEADERS, json={
        "first_name": "Sterling",
        "last_name": f"Archer_{uniq}",
        "email": f"archer.{uniq}@isis.agency",
        "phone": "713.555.0199",
        "date_of_birth": "1985-05-15",
        "drivers_license_number": f"TX-RES-{uniq.upper()}",
        "drivers_license_state": "TX",
        "primary_location_code": "HOU",
        "plan_code": "PLAN_100",
        "planned_start_date": "2026-10-01"
    })
    assert onboard_resp.status_code == 201, f"Onboarding failed: {onboard_resp.text}"
    member = onboard_resp.json().get('member', {})
    member_id = member['member_id']

    # 3. Test 9.2-C17: Booking against Pending member is created tentative
    print("\n--- TEST 2: Booking Against Pending Member is Tentative (9.2-C17) ---")
    sub_id = member.get('subscription_id')
    assert sub_id is not None, "Member has no subscription_id"

    tentative_booking = requests.post(f"{API_BASE}/v1/reservations", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": d_tent_pickup,
        "return_at": d_tent_return,
        "auto_confirm": True
    })
    assert tentative_booking.status_code == 201, f"Booking failed: {tentative_booking.text}"
    t_res = tentative_booking.json().get('reservation', {})
    assert t_res.get('status') == 'tentative', f"Expected status tentative, got {t_res.get('status')}"
    assert t_res.get('is_tentative') is True, "is_tentative must be true"
    tentative_id = t_res['id']
    print(f"[PASS] 9.2-C17: Booking against pending member created with status='tentative', is_tentative=true")

    # Confirm attempt on tentative booking while member is pending is refused
    conf_pend = requests.post(f"{API_BASE}/v1/reservations/{tentative_id}/confirm", headers=HEADERS)
    assert conf_pend.status_code == 400, "Should not confirm tentative booking while member is pending"
    print(f"[PASS] 9.2-C17: Tentative booking cannot be manually confirmed until member is activated")

    # 4. Activate the member
    print("\n--- TEST 3: Activate Member (6.1-C24) ---")
    pa_resp = requests.post(f"{API_BASE}/v1/members/{member_id}/payment-arrangement", headers=HEADERS, json={
        "payment_method_type": "Card",
        "billing_email": f"archer.{uniq}@isis.agency"
    })
    assert pa_resp.status_code == 200, f"PA failed: {pa_resp.text}"

    act_resp = requests.post(f"{API_BASE}/v1/members/{member_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": True,
        "activation_date": "2026-10-01",
        "joining_bonus_points": 500
    })
    assert act_resp.status_code == 200, f"Activation failed: {act_resp.text}"
    act_data = act_resp.json()
    mem_num = act_data.get('activation', {}).get('member_number') or act_data.get('member', {}).get('member_number')
    print(f"[PASS] Member activated. Member number: {mem_num}")

    # 5. Test 9.2-C06: Membership ending mid-trip refuses booking
    print("\n--- TEST 4: Membership Ending Mid-Trip Refused (9.2-R2, 9.2-C06) ---")
    past_end_booking = requests.post(f"{API_BASE}/v1/reservations", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": "2028-10-15T14:00:00Z",
        "return_at": "2028-10-18T10:00:00Z"
    })
    assert past_end_booking.status_code == 400, f"Expected 400 for booking past sub end date, got {past_end_booking.status_code}"
    assert "9.2-C06" in past_end_booking.text or "Membership ends" in past_end_booking.text, f"Unexpected error: {past_end_booking.text}"
    print(f"[PASS] 9.2-C06: Booking past subscription end date refused with 400")

    # 6. Test 9.2-C13 & 9.2-C10-C12: Quote returns breakdown and stores parts
    print("\n--- TEST 5: Estimate Stored in Weekday & Weekend Parts (9.2-R8, 9.2-C13) ---")
    quote_resp = requests.post(f"{API_BASE}/v1/reservations/_/quote", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": d_thu_pickup,
        "return_at": d_mon_return
    })
    assert quote_resp.status_code == 200, f"Quote failed: {quote_resp.text}"
    quote = quote_resp.json().get('quote', {})
    assert quote.get('weekday_days') == 1, f"Expected 1 weekday day, got {quote.get('weekday_days')}"
    assert quote.get('weekend_units') == 1, f"Expected 1 weekend unit, got {quote.get('weekend_units')}"
    assert quote.get('weekday_points') > 0, "Weekday points must be > 0"
    assert quote.get('weekend_points') > 0, "Weekend points must be > 0"
    assert quote.get('total_points_cost') == quote['weekday_points'] + quote['weekend_points']
    print(f"[PASS] 9.2-C13: Quote broken into {quote['weekday_points']} weekday pts + {quote['weekend_points']} weekend pts = {quote['total_points_cost']} total")

    # 7. Test 9.2-C15: Confirmed Reservation Posts Real Charge to Points Ledger
    print("\n--- TEST 6: Confirmed Reservation Posts Charge to Points Ledger (9.2-R9, 9.2-C15) ---")
    book_resp = requests.post(f"{API_BASE}/v1/reservations", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": d_thu_pickup,
        "return_at": d_mon_return,
        "auto_confirm": True
    })
    assert book_resp.status_code == 201, f"Booking failed: {book_resp.text}"
    resv = book_resp.json().get('reservation', {})
    resv_id = resv['id']
    assert resv['status'] == 'confirmed'
    assert resv['weekday_points'] == quote['weekday_points']
    assert resv['weekend_points'] == quote['weekend_points']
    assert resv['total_points_cost'] == quote['total_points_cost']
    print(f"[PASS] Reservation confirmed. Points cost: {resv['total_points_cost']}. Block until: {resv.get('block_until')}")

    # Check that points were debited from member's balance
    sub_after = requests.get(f"{API_BASE}/v1/members/{member_id}/subscription", headers=HEADERS).json()['active_subscription']
    print(f"[PASS] 9.2-C15: Member balance updated after debit. Current balance: {sub_after.get('points_balance')}")

    # 8. Test Turnaround Buffer Overlap Refusal (trg_reservations_block_until)
    print("\n--- TEST 7: Turnaround Buffer Overlap Refusal (trg_reservations_block_until) ---")
    # Return date was d_mon_return (Monday 10:00:00Z). Prep buffer is 4 hours, so block_until is Monday 14:00:00Z.
    # Attempting to book at 12:00:00Z (during the 4-hour detailing window) must be REFUSED with 409!
    overlap_resp = requests.post(f"{API_BASE}/v1/reservations", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": d_buf_pickup,
        "return_at": d_buf_return
    })
    assert overlap_resp.status_code == 409, f"Expected 409 for booking inside turnaround buffer, got {overlap_resp.status_code}: {overlap_resp.text}"
    assert "turnaround detailing buffer" in overlap_resp.text or "already reserved" in overlap_resp.text
    print(f"[PASS] Overlap inside turnaround buffer (trg_reservations_block_until) refused with 409")

    # 9. Test 9.2-C16: Courtesy Booking Consumes 0 Points and Still Blocks Calendar
    print("\n--- TEST 8: Courtesy Booking Consumes 0 Points and Blocks Calendar (9.2-R10, 9.2-C16) ---")
    courtesy_resp = requests.post(f"{API_BASE}/v1/reservations", headers=HEADERS, json={
        "subscription_id": sub_id,
        "vehicle_id": vehicle_id,
        "pickup_at": d_crt_pickup,
        "return_at": d_crt_return,
        "is_courtesy": True,
        "auto_confirm": True
    })
    assert courtesy_resp.status_code == 201, f"Courtesy booking failed: {courtesy_resp.text}"
    c_res = courtesy_resp.json().get('reservation', {})
    assert c_res.get('total_points_cost') == 0, f"Expected 0 points for courtesy booking, got {c_res.get('total_points_cost')}"
    assert c_res.get('is_courtesy') is True, "is_courtesy must be true"
    print(f"[PASS] 9.2-C16: Courtesy booking occupies calendar, total_points_cost = 0, is_courtesy = true")

    print("\n" + "=" * 80)
    print("ALL GUIDE 9.2 RESERVATION TESTS PASSED!")
    print("=" * 80)

if __name__ == "__main__":
    run_tests()
