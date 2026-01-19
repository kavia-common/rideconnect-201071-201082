-- RideConnect PostgreSQL schema + seed (idempotent)
-- This script is safe to run multiple times.
-- It is executed by database/startup.sh after PostgreSQL is up.

BEGIN;

-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('rider', 'driver');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ride_status') THEN
        CREATE TYPE ride_status AS ENUM ('requested', 'assigned', 'enroute', 'started', 'completed', 'canceled');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
        CREATE TYPE payment_status AS ENUM ('pending', 'authorized', 'captured', 'failed');
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role user_role NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS drivers (
    id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    vehicle_info TEXT,
    license_no TEXT,
    rating NUMERIC(3,2) NOT NULL DEFAULT 5.00,
    is_available BOOLEAN NOT NULL DEFAULT FALSE,
    location_lat DOUBLE PRECISION,
    location_lng DOUBLE PRECISION,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id UUID REFERENCES users(id) ON DELETE SET NULL,
    origin_lat DOUBLE PRECISION NOT NULL,
    origin_lng DOUBLE PRECISION NOT NULL,
    dest_lat DOUBLE PRECISION NOT NULL,
    dest_lng DOUBLE PRECISION NOT NULL,
    status ride_status NOT NULL DEFAULT 'requested',
    fare_cents INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ride_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    amount_cents INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    status payment_status NOT NULL DEFAULT 'pending',
    processor_ref TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------
-- users.email already has a UNIQUE index due to constraint, but we keep this
-- section for clarity and future additions.
CREATE INDEX IF NOT EXISTS idx_drivers_is_available ON drivers(is_available);
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_created_at ON rides(created_at);

COMMIT;

-- -----------------------------------------------------------------------------
-- Seed data (minimal, for local usage)
-- Use deterministic UUIDs so other containers can rely on stable IDs in dev.
-- -----------------------------------------------------------------------------
BEGIN;

-- Users (riders)
INSERT INTO users (id, name, email, password_hash, role)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'Rita Rider', 'rita.rider@example.com', 'dev_hash_rita', 'rider'),
    ('00000000-0000-0000-0000-000000000002', 'Rob Rider',  'rob.rider@example.com',  'dev_hash_rob',  'rider')
ON CONFLICT (email) DO NOTHING;

-- Users (drivers)
INSERT INTO users (id, name, email, password_hash, role)
VALUES
    ('00000000-0000-0000-0000-000000000101', 'Dina Driver', 'dina.driver@example.com', 'dev_hash_dina', 'driver'),
    ('00000000-0000-0000-0000-000000000102', 'Dan Driver',  'dan.driver@example.com',  'dev_hash_dan',  'driver')
ON CONFLICT (email) DO NOTHING;

-- Drivers profiles
INSERT INTO drivers (id, vehicle_info, license_no, rating, is_available, location_lat, location_lng)
VALUES
    ('00000000-0000-0000-0000-000000000101', 'Toyota Prius - Blue - ABC-123', 'LIC-DINA-001', 4.90, TRUE,  37.7749, -122.4194),
    ('00000000-0000-0000-0000-000000000102', 'Honda Civic - White - XYZ-789', 'LIC-DAN-002',  4.70, FALSE, 37.7849, -122.4094)
ON CONFLICT (id) DO NOTHING;

-- Completed rides
INSERT INTO rides (
    id, rider_id, driver_id,
    origin_lat, origin_lng, dest_lat, dest_lng,
    status, fare_cents, created_at, updated_at
) VALUES
    (
        '00000000-0000-0000-0000-000000001001',
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000101',
        37.7730, -122.4310, 37.7840, -122.4090,
        'completed', 1299,
        now() - interval '3 days', now() - interval '3 days'
    ),
    (
        '00000000-0000-0000-0000-000000001002',
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000102',
        37.7600, -122.4470, 37.7930, -122.3930,
        'completed', 1899,
        now() - interval '1 day', now() - interval '1 day'
    )
ON CONFLICT (id) DO NOTHING;

-- Ride events (for completed rides)
INSERT INTO ride_events (ride_id, event_type, payload, created_at)
VALUES
    ('00000000-0000-0000-0000-000000001001', 'ride_completed', '{"note":"Seed ride completed"}'::jsonb, now() - interval '3 days'),
    ('00000000-0000-0000-0000-000000001002', 'ride_completed', '{"note":"Seed ride completed"}'::jsonb, now() - interval '1 day')
ON CONFLICT DO NOTHING;

-- Payments for completed rides
INSERT INTO payments (ride_id, amount_cents, currency, status, processor_ref, created_at)
VALUES
    ('00000000-0000-0000-0000-000000001001', 1299, 'USD', 'captured', 'seed_proc_1001', now() - interval '3 days'),
    ('00000000-0000-0000-0000-000000001002', 1899, 'USD', 'captured', 'seed_proc_1002', now() - interval '1 day')
ON CONFLICT DO NOTHING;

COMMIT;
