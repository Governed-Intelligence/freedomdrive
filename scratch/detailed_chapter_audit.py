import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

guides = kb.get('guides', [])

def parse_id(gid_str):
    parts = str(gid_str).split('.')
    return [int(p) if p.isdigit() else p for p in parts]

sorted_guides = sorted(guides, key=lambda x: parse_id(x.get('guide_id') or x.get('id') or x.get('number')))

chapters_meta = {
    '1': 'Platform Architecture, Mobile & Portal Touchpoints',
    '2': 'User Accounts, Roles, Auth & Access Security',
    '3': 'Branch Network, Locations, Capacity & Regional Access',
    '4': 'Staff Management, Operations & Role Hierarchies',
    '5': 'Vendors, Service Providers & Logistics Compliance',
    '6': 'Member Lifecycle, Onboarding, Identity & Financial Arrangements',
    '7': 'Membership Tiers, Points Economy & Seasonal Rate Cards',
    '8': 'Fleet Management, Vehicle Intake, Turnaround & Bookability',
    '9': 'Vehicle Reservations, Turnaround Detailing & Booking Gates',
    '10': 'Trip Execution, Dispatch, Return Custody & Settlement',
    '11': 'Vehicle Inspections, Photography, Severity & Damage Tracking',
    '12': 'Points & Perks Ledger, Carry-Forward & Statements',
    '13': 'Tasks Management, Checklists & Operational Audit Trail',
    '14': 'Automations, Workflows, Trigger Rules & Webhooks',
    '15': 'Member & Staff Multi-Channel Notifications Engine',
    '16': 'Vehicle Fractional Partners, Availability & Owner Payouts',
    '17': 'Member Car Registry, Private Storage & Concierge Garage',
    '18': 'Club Events, Driving Tours, Capacity & Check-In',
    '19': 'Data Capture Wizards, Catalog & Validation Forms',
    '20': 'Dynamic Form Engine, Inspections & Defect Mapping Layer',
    '21': 'Document Repository, Categories, Retention & Legal Hold',
    '22': 'Reporting Engine, Operational Registry & Automated Exports',
    '23': 'External Integrations, REST/Webhook Bridges & Club Partners',
    '24': 'Enterprise Identifiers, Global Lifecycle & Audit Change History'
}

print(f"Total Guides: {len(sorted_guides)}")
for ch_num in sorted(chapters_meta.keys(), key=lambda x: int(x)):
    ch_guides = [g for g in sorted_guides if str(g.get('guide_id') or g.get('id') or g.get('number')).split('.')[0] == ch_num]
    total_rules = sum(len(g.get('rules', [])) for g in ch_guides)
    total_chk = sum(len(g.get('checklist', [])) for g in ch_guides)
    print(f"Ch {ch_num:2}: {chapters_meta[ch_num]} ({len(ch_guides)} guides, {total_rules} rules, {total_chk} checklist items)")
