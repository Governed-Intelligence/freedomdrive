-- =============================================================================
-- Migration 027: Add 'tentative' to fs.reservation_status enum
-- Required for Guide 9.2-C17 (Bookings against Pending members are tentative)
-- =============================================================================

ALTER TYPE fs.reservation_status ADD VALUE IF NOT EXISTS 'tentative';
