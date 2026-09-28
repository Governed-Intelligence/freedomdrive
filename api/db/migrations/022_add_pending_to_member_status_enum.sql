-- =============================================================================
-- Migration 022: Add 'pending', 'former', 'voided' to fs.member_status enum
-- Required for Guide 6.1-C03, 6.3-C01, 6.3-R11 (A member with no number is Pending)
-- =============================================================================

ALTER TYPE fs.member_status ADD VALUE IF NOT EXISTS 'pending';
ALTER TYPE fs.member_status ADD VALUE IF NOT EXISTS 'former';
ALTER TYPE fs.member_status ADD VALUE IF NOT EXISTS 'voided';
