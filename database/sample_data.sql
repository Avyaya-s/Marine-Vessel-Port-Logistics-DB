-- =====================================================================
-- sample_data.sql : small hand-written data set for testing the schema
-- and triggers.  Run on a fresh schema (identity columns start at 1).
-- The full synthetic data set comes later from data/generate_data.py.
-- "Now" in this data is roughly 2026-10-16.
-- =====================================================================

BEGIN;

INSERT INTO vessel (imo_number, mmsi, vessel_name, flag, vessel_type, loa, draft) VALUES
('9321483', '563012340', 'Ocean Pioneer',  'Singapore',        'Container',     300.00, 13.50),
('9412347', '636091234', 'Coral Trader',   'Liberia',          'Container',     335.00, 14.20),
('9527817', '538007712', 'Iron Monarch',   'Marshall Islands', 'Bulk',          229.00, 12.10),
('9633070', '419000456', 'Ganga Spirit',   'India',            'Tanker',        250.00, 13.80),
('9705122', '351234000', 'Blue Horizon',   'Panama',           'General Cargo', 160.00,  8.50),
('9876543', '229876000', 'Malta Express',  'Malta',            'Container',     270.00, 12.80);

-- company_id 1-10 in insertion order
INSERT INTO company (company_name, iec_code, company_type) VALUES
('Seaways Shipping Agency',       NULL,         'agent'),      -- 1
('Bluewater Maritime Agents',     NULL,         'agent'),      -- 2
('Harbor Line Agencies',          NULL,         'agent'),      -- 3
('Shenzhen Bright Electronics',   NULL,         'shipper'),    -- 4  foreign: no IEC
('Rotterdam Machinery BV',        NULL,         'shipper'),    -- 5
('Deccan Textiles Pvt Ltd',       'AABCD1234E', 'shipper'),    -- 6  Indian exporter
('Kaveri Imports Pvt Ltd',        'AACCK5678F', 'consignee'),  -- 7
('Nilgiri Trading Co',            'AADCN9012G', 'consignee'),  -- 8
('Gulf Retail LLC',               NULL,         'consignee'),  -- 9  foreign buyer
('Pacific Coal Resources Pty',    NULL,         'shipper');    -- 10

INSERT INTO berth (berth_number, max_loa, max_draft, cargo_type) VALUES
('B01', 350.00, 15.00, 'Container'),
('B02', 300.00, 13.50, 'Container'),
('B03', 260.00, 13.00, 'Bulk'),
('B04', 280.00, 15.50, 'Tanker'),
('B05', 200.00, 10.00, 'General Cargo');

-- call_id 1-6.  One call in each status, plus one not yet allocated.
INSERT INTO port_call (imo_number, agent_id, berth_number, berth_start, berth_end,
                       eta, predicted_eta, ata, atd, call_status) VALUES
-- 1: finished visit
('9321483', 1, 'B02', '2026-10-10 08:00+05:30', '2026-10-11 20:00+05:30',
 '2026-10-10 06:00+05:30', '2026-10-10 05:45+05:30', '2026-10-10 05:30+05:30', '2026-10-11 21:00+05:30', 'Departed'),
-- 2: alongside now
('9412347', 2, 'B01', '2026-10-15 14:00+05:30', '2026-10-17 02:00+05:30',
 '2026-10-15 10:00+05:30', '2026-10-15 11:00+05:30', '2026-10-15 11:20+05:30', NULL, 'Berthed'),
-- 3: at anchorage, berth booked for later today
('9527817', 3, 'B03', '2026-10-16 18:00+05:30', '2026-10-18 06:00+05:30',
 '2026-10-16 06:00+05:30', '2026-10-16 06:45+05:30', '2026-10-16 07:10+05:30', NULL, 'Waiting'),
-- 4: inbound, berth pre-allocated
('9633070', 1, 'B04', '2026-10-18 04:00+05:30', '2026-10-19 10:00+05:30',
 '2026-10-18 01:00+05:30', '2026-10-18 02:30+05:30', NULL, NULL, 'Expected'),
-- 5: inbound, no berth yet (allocate_berth will handle this one)
('9705122', 2, NULL, NULL, NULL,
 '2026-10-19 12:00+05:30', NULL, NULL, NULL, 'Expected'),
-- 6: inbound, same berth as call 1 but a later window
('9876543', 3, 'B02', '2026-10-17 08:00+05:30', '2026-10-18 08:00+05:30',
 '2026-10-17 05:00+05:30', NULL, NULL, NULL, 'Expected');

INSERT INTO shipping_manifest (manifest_no, call_id, manifest_type, filing_date) VALUES
('IGM-2026-0001', 1, 'IGM', '2026-10-09'),
('EGM-2026-0001', 1, 'EGM', '2026-10-11'),
('IGM-2026-0002', 2, 'IGM', '2026-10-14'),
('IGM-2026-0003', 3, 'IGM', '2026-10-15');

INSERT INTO shipment (shipment_no, manifest_no, shipper_id, consignee_id, cargo_description,
                      origin_port, hs_code, cargo_quantity, gross_weight) VALUES
('BL-SZX-260001', 'IGM-2026-0001', 4,  7, 'Lithium-ion battery packs',  'CNSZX', '85076000', 1200,    18500.00),
('BL-SZX-260002', 'IGM-2026-0001', 4,  8, 'LED television panels',      'CNSZX', '85287200',  800,     9600.00),
('BL-NSA-260003', 'EGM-2026-0001', 6,  9, 'Cotton bed linen',           'INNSA', '63022100', 5000,    14200.00),
('BL-RTM-260004', 'IGM-2026-0002', 5,  7, 'CNC milling machines',       'NLRTM', '84596100',    6,    42000.00),
('BL-RTM-260005', 'IGM-2026-0002', 5,  8, 'Hydraulic pumps',            'NLRTM', '84136090',  300,     7800.00),
('BL-NTL-260006', 'IGM-2026-0003', 10, 7, 'Steam coal in bulk',         'AUNTL', '27011200',    1, 65000000.00);

INSERT INTO container (container_no, iso_type, size) VALUES
('MSCU1234565', '22G1', 20),
('MSCU7654321', '45G1', 40),
('TGHU3456789', '45R1', 40),   -- reefer
('CMAU9988776', '22G1', 20),
('OOLU5544332', '45G1', 40),
('HLXU1122334', 'L5G1', 45),
('TCLU6677889', '22G1', 20);

-- coal (BL-NTL-260006) is bulk cargo, so it has no containers
INSERT INTO shipment_container (shipment_no, container_no, seal_no, container_status) VALUES
('BL-SZX-260001', 'MSCU1234565', 'SL4410021', 'Released'),
('BL-SZX-260001', 'MSCU7654321', 'SL4410022', 'Released'),
('BL-SZX-260002', 'CMAU9988776', 'SL4410035', 'Held'),
('BL-NSA-260003', 'TCLU6677889', 'SL7720190', 'Loaded'),
('BL-RTM-260004', 'OOLU5544332', 'SL9031457', 'Discharged'),
('BL-RTM-260004', 'HLXU1122334', 'SL9031458', 'Discharged'),
('BL-RTM-260005', 'TGHU3456789', 'SL9031502', 'Discharged');

INSERT INTO customs_filing (filing_no, shipment_no, filing_type, filing_date,
                            declared_value, duty_amount, filing_status, risk_score) VALUES
('BE-2026-000101', 'BL-SZX-260001', 'Bill of Entry', '2026-10-10',  4250000.00, 850000.00, 'Cleared',      0.120),
('BE-2026-000102', 'BL-SZX-260002', 'Bill of Entry', '2026-10-10',   900000.00,      NULL, 'Held',         0.870),
('SB-2026-000201', 'BL-NSA-260003', 'Shipping Bill', '2026-10-09',  2100000.00,      0.00, 'Cleared',      0.050),
('BE-2026-000103', 'BL-RTM-260004', 'Bill of Entry', '2026-10-15', 18500000.00,      NULL, 'Under Review', 0.310),
('BE-2026-000104', 'BL-RTM-260005', 'Bill of Entry', '2026-10-15',  2300000.00,      NULL, 'Filed',        NULL);

INSERT INTO inspection (filing_no, inspection_no, inspection_date, officer_name, result, remarks) VALUES
('BE-2026-000101', 1, '2026-10-10', 'A. Khan',  'Clear',       'Random check; contents match packing list'),
('BE-2026-000102', 1, '2026-10-11', 'R. Menon', 'Discrepancy', 'Declared unit value about 60% below typical for HS 85287200'),
('BE-2026-000102', 2, '2026-10-13', 'S. Iyer',  'Pending',     'Re-examination after revised invoice');

COMMIT;
