-- Seed data for the two small lookup tables.
-- Run this after 01_schema_setup.sql and before loading users and events.

INSERT INTO dim_locations (location_id, city, country, latitude, longitude)
VALUES
    (1, 'Mumbai',    'India',     19.0760,  72.8777),
    (2, 'Delhi',     'India',     28.7041,  77.1025),
    (3, 'London',    'UK',        51.5074,  -0.1278),
    (4, 'Frankfurt', 'Germany',   50.1109,   8.6821),
    (5, 'New York',  'USA',       40.7128, -74.0060),
    (6, 'Singapore', 'Singapore',  1.3521, 103.8198)
ON CONFLICT (location_id) DO NOTHING;

INSERT INTO dim_devices (device_id, device_type, os, browser)
VALUES
    (1, 'Laptop', 'Windows 11', 'Chrome'),
    (2, 'Laptop', 'Windows 10', 'Edge'),
    (3, 'Laptop', 'macOS',      'Safari'),
    (4, 'Laptop', 'Ubuntu',     'Firefox'),
    (5, 'Mobile', 'Android',    'Chrome'),
    (6, 'Mobile', 'iOS',        'Safari')
ON CONFLICT (device_id) DO NOTHING;