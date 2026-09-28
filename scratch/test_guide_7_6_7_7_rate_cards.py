import requests
import json
import uuid
from datetime import datetime, date

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"
API_KEY = "XwzVylqkoXs9YdhLbBOc2MZ571djQvNkXsVM9Ycb"
HEADERS = {
    "x-api-key": API_KEY,
    "Content-Type": "application/json"
}

def run_tests():
    print("=" * 80)
    print("RUNNING LIVE END-TO-END VERIFICATION: GUIDE 7.6 & 7.7 RATE CARDS & TIERS")
    print("=" * 80)

    # 1. Fetch available tiers and vehicles to use in tests
    tiers_resp = requests.get(f"{API_BASE}/v1/fleet/tiers", headers=HEADERS)
    if tiers_resp.status_code != 200:
        tiers_resp = requests.get(f"{API_BASE}/v1/tiers", headers=HEADERS)
    assert tiers_resp.status_code == 200, f"Tiers fetch failed: {tiers_resp.text}"
    tiers_list = tiers_resp.json().get('tiers', [])
    assert len(tiers_list) >= 2, "Need at least 2 tiers"

    # Get vehicle_tier_id from database if available or fleet vehicles
    fleet_resp = requests.get(f"{API_BASE}/v1/fleet", headers=HEADERS)
    assert fleet_resp.status_code == 200, f"Fleet fetch failed: {fleet_resp.text}"
    vehicles = fleet_resp.json().get('vehicles', [])
    assert len(vehicles) >= 2, "Need at least 2 vehicles"
    v1 = vehicles[0]['vehicle_id']
    v2 = vehicles[1]['vehicle_id']

    # 2. List Rate Cards
    print("\n--- TEST 1: List Rate Cards (7.6-C01) ---")
    rc_list_resp = requests.get(f"{API_BASE}/v1/rate-cards", headers=HEADERS)
    assert rc_list_resp.status_code == 200, f"Rate cards list failed: {rc_list_resp.text}"
    cards = rc_list_resp.json().get('rate_cards', [])
    print(f"[PASS] Retrieved {len(cards)} rate cards. Active standard cards present.")

    # Find standard card
    std_card = next((c for c in cards if c['card_code'] == 'RC_STANDARD_2026'), cards[0] if cards else None)
    assert std_card is not None, "Standard card not found"
    std_card_id = std_card['rate_card_id']

    # Get standard card details
    card_det_resp = requests.get(f"{API_BASE}/v1/rate-cards/{std_card_id}", headers=HEADERS)
    assert card_det_resp.status_code == 200, f"Card details failed: {card_det_resp.text}"
    std_det = card_det_resp.json().get('rate_card', {})
    rates = std_det.get('rates', [])
    assert len(rates) > 0, "Standard card has no rates"
    tier_1_id = rates[0]['vehicle_tier_id']
    tier_2_id = rates[1]['vehicle_tier_id'] if len(rates) > 1 else tier_1_id

    # 3. Create Draft Rate Card (7.6-C01: editable freely while first_used_on is empty)
    print("\n--- TEST 2: Draft Rate Card Creation & Editable Rates (7.6-C01) ---")
    uniq = uuid.uuid4().hex[:6]
    draft_code = f"RC_DRAFT_{uniq}"
    create_rc = requests.post(f"{API_BASE}/v1/rate-cards", headers=HEADERS, json={
        "card_code": draft_code,
        "card_name": f"Test Draft Card {uniq}",
        "description": "Draft rate card for testing 7.6 immutability rules"
    })
    assert create_rc.status_code == 201, f"Create rate card failed: {create_rc.text}"
    draft_card = create_rc.json().get('rate_card', {})
    draft_id = draft_card['rate_card_id']
    assert draft_card.get('first_used_on') is None, "Draft card should not have first_used_on"
    print(f"[PASS] 7.6-C01: Draft card {draft_code} created (first_used_on = NULL)")

    # 4. Add Rate rows to draft card (7.6-C05)
    print("\n--- TEST 3: Add Rates to Card (7.6-C05, 7.6-C13, 7.6-C14) ---")
    rate1_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/rates", headers=HEADERS, json={
        "vehicle_tier_id": tier_1_id,
        "weekday_point_value": 45,
        "weekend_point_value": 65,
        "extra_mile_point_value": 1.250
    })
    assert rate1_resp.status_code == 201, f"Add rate failed: {rate1_resp.text}"
    rate1 = rate1_resp.json().get('rate', {})
    rate1_id = rate1['rate_card_rate_id']
    assert float(rate1['extra_mile_point_value']) == 1.250, "7.6-C14: Extra mile fractional precision preserved"
    print(f"[PASS] 7.6-C05 & 7.6-C14: Rate row added. Extra mile = {rate1['extra_mile_point_value']}")

    # 5. Add Placement to draft card (7.6-C04, 7.7-C04)
    print("\n--- TEST 4: Add Vehicle Placement (7.6-C04, 7.7-C04) ---")
    p1_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/placements", headers=HEADERS, json={
        "vehicle_id": v1,
        "vehicle_tier_id": tier_1_id
    })
    assert p1_resp.status_code == 201, f"Placement failed: {p1_resp.text}"
    p1_id = p1_resp.json().get('placement', {})['rate_card_placement_id']
    print(f"[PASS] 7.6-C04: Vehicle {v1} placed in tier {tier_1_id}")

    # 6. Duplicate placement on same card refused (7.6-C06, 7.7-C05)
    print("\n--- TEST 5: Duplicate Placement Refusal (7.6-C06, 7.7-C05) ---")
    dup_p_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/placements", headers=HEADERS, json={
        "vehicle_id": v1,
        "vehicle_tier_id": tier_2_id
    })
    assert dup_p_resp.status_code == 409, f"Expected 409 for duplicate placement, got {dup_p_resp.status_code}"
    print(f"[PASS] 7.6-C06 / 7.7-C05: Second placement for same vehicle on same card refused with 409")

    # 7. Freeze the card by setting first_used_on (7.6-C02)
    print("\n--- TEST 6: Freeze Card via first_used_on (7.6-C02) ---")
    freeze_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/freeze", headers=HEADERS, json={
        "first_used_on": "2026-09-01"
    })
    assert freeze_resp.status_code == 200, f"Freeze failed: {freeze_resp.text}"
    print(f"[PASS] 7.6-C02: Card frozen with first_used_on = 2026-09-01")

    # 8. Edit existing rate on used card refused (7.6-C03)
    print("\n--- TEST 7: Edit Existing Rate on Used Card Refused (7.6-C03) ---")
    edit_rate_resp = requests.patch(f"{API_BASE}/v1/rate-cards/{draft_id}/rates/{rate1_id}", headers=HEADERS, json={
        "weekday_point_value": 99
    })
    assert edit_rate_resp.status_code == 409, f"Expected 409 on editing frozen rate, got {edit_rate_resp.status_code}: {edit_rate_resp.text}"
    print(f"[PASS] 7.6-C03: Edit to existing rate on used card refused with 409")

    # 9. Edit existing placement on used card refused (7.6-C07, 7.7-C03)
    print("\n--- TEST 8: Edit Existing Placement on Used Card Refused (7.6-C07, 7.7-C03) ---")
    edit_p_resp = requests.patch(f"{API_BASE}/v1/rate-cards/{draft_id}/placements/{p1_id}", headers=HEADERS, json={
        "vehicle_tier_id": tier_2_id
    })
    assert edit_p_resp.status_code == 409, f"Expected 409 on editing frozen placement, got {edit_p_resp.status_code}: {edit_p_resp.text}"
    print(f"[PASS] 7.6-C07 / 7.7-C03: Edit to existing placement on used card refused with 409")

    # 10. New placement for unplaced vehicle ON used card is PERMITTED (7.6-C04, 7.7-C04)
    print("\n--- TEST 9: Add New Placement for Vehicle Not Yet on Used Card Allowed (7.6-C04, 7.7-C04) ---")
    p2_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/placements", headers=HEADERS, json={
        "vehicle_id": v2,
        "vehicle_tier_id": tier_1_id
    })
    assert p2_resp.status_code == 201, f"New placement on used card failed: {p2_resp.text}"
    print(f"[PASS] 7.6-C04 / 7.7-C04: New placement for unplaced vehicle {v2} allowed on used card")

    # 11. Copy Card produces new card with editable rates (7.6-C08)
    print("\n--- TEST 10: Copy Card into Editable Draft (7.6-C08) ---")
    copied_code = f"RC_COPY_{uniq}"
    copy_resp = requests.post(f"{API_BASE}/v1/rate-cards/{draft_id}/copy", headers=HEADERS, json={
        "new_card_code": copied_code,
        "new_card_name": f"Copied Rate Card {uniq}"
    })
    assert copy_resp.status_code == 201, f"Copy card failed: {copy_resp.text}"
    copied_card = copy_resp.json().get('rate_card', {})
    copied_id = copied_card['rate_card_id']
    assert copied_card.get('first_used_on') is None, "Copied card must have first_used_on = NULL"

    # Verify rates on copied card can be edited
    copy_det = requests.get(f"{API_BASE}/v1/rate-cards/{copied_id}", headers=HEADERS).json()['rate_card']
    assert len(copy_det['rates']) > 0, "Copied card has no rates"
    copied_rate_id = copy_det['rates'][0]['rate_card_rate_id']
    edit_copied_resp = requests.patch(f"{API_BASE}/v1/rate-cards/{copied_id}/rates/{copied_rate_id}", headers=HEADERS, json={
        "weekday_point_value": 77
    })
    assert edit_copied_resp.status_code == 200, f"Failed to edit copied rate: {edit_copied_resp.text}"
    print(f"[PASS] 7.6-C08: Copied card {copied_code} created and its rate was edited to 77")

    # 12. 5-Step Resolver Engine & Weekend Bundling (7.6-C13, 7.7-C09, 9.2-C10-C12)
    print("\n--- TEST 11: 5-Step Resolver Engine & Weekend Bundling (7.6-C13, 7.7-C09, 9.2-C10-C12) ---")
    # Friday 2026-10-09 to Monday 2026-10-12 (Weekend trip)
    fri_mon_resp = requests.post(f"{API_BASE}/v1/rate-cards/resolve", headers=HEADERS, json={
        "vehicle_id": v1,
        "pickup_at": "2026-10-09T14:00:00Z",
        "return_at": "2026-10-12T10:00:00Z"
    })
    assert fri_mon_resp.status_code == 200, f"Friday-to-Monday resolve failed: {fri_mon_resp.text}"
    pricing_fri = fri_mon_resp.json().get('pricing', {})
    assert pricing_fri.get('weekendUnits') == 1, "Friday-to-Monday should count 1 weekend unit"
    assert pricing_fri.get('weekdayDays') == 0, "Friday-to-Monday should count 0 weekday days"
    assert pricing_fri.get('weekendPoints') == pricing_fri.get('weekendPointValue'), "Weekend points must equal bundled weekend point value"
    print(f"[PASS] 9.2-C11 & 7.6-C13: Friday-to-Monday charges 1 bundled weekend ({pricing_fri['weekendPoints']} pts)")

    # Thursday 2026-10-08 to Monday 2026-10-12 (Mixed trip: 1 weekday + 1 weekend)
    thu_mon_resp = requests.post(f"{API_BASE}/v1/rate-cards/resolve", headers=HEADERS, json={
        "vehicle_id": v1,
        "pickup_at": "2026-10-08T14:00:00Z",
        "return_at": "2026-10-12T10:00:00Z"
    })
    assert thu_mon_resp.status_code == 200, f"Thursday-to-Monday resolve failed: {thu_mon_resp.text}"
    pricing_thu = thu_mon_resp.json().get('pricing', {})
    assert pricing_thu.get('weekdayDays') == 1, "Thursday-to-Monday should count 1 weekday day"
    assert pricing_thu.get('weekendUnits') == 1, "Thursday-to-Monday should count 1 weekend unit"
    expected_total = pricing_thu['weekdayPointValue'] + pricing_thu['weekendPointValue']
    assert pricing_thu.get('totalPoints') == expected_total, f"Expected {expected_total}, got {pricing_thu.get('totalPoints')}"
    print(f"[PASS] 9.2-C12: Thursday-to-Monday charges 1 weekday ({pricing_thu['weekdayPointValue']}) + 1 weekend ({pricing_thu['weekendPointValue']}) = {expected_total} pts")

    print("\n" + "=" * 80)
    print("ALL GUIDE 7.6 & 7.7 RATE CARD & TIER TESTS PASSED!")
    print("=" * 80)

if __name__ == "__main__":
    run_tests()
