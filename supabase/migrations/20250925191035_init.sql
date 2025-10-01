-- Enable PostGIS extensions for geospatial data
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create enum for time periods
CREATE TYPE time_period AS ENUM ('1609', '1660', '1776');

-- Create enum for data types
CREATE TYPE data_type AS ENUM ('raster', 'vector', 'dem', 'historical_map');

-- Create enum for data categories
CREATE TYPE data_category AS ENUM ('parcels', 'buildings', 'boundaries', 'masks', 'elevation', 'historical');

-- Create enum for user roles
CREATE TYPE user_role AS ENUM ('viewer', 'editor', 'admin');

-- Create enum for media types
CREATE TYPE media_type AS ENUM ('photo', 'map', 'audio', 'video', 'glb', 'usd', 'scan');

-- Create enum for media roles
CREATE TYPE media_role AS ENUM ('reference', 'texture', 'ambient_audio');

-- User profiles table (extends Supabase auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'viewer',
    display_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sources table for attribution and provenance
CREATE TABLE sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    citation TEXT,
    url TEXT,
    license TEXT,
    archive_ref TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Main data sources table (simplified)
CREATE TABLE data_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    time_period time_period NOT NULL,
    data_type data_type NOT NULL,
    data_category data_category NOT NULL,
    file_path VARCHAR(500),
    coordinate_system VARCHAR(50) DEFAULT 'EPSG:3857',
    source_id UUID REFERENCES sources(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Historical building parcels table (with temporal fields)
CREATE TABLE building_parcels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES data_sources(id),
    parcel_id VARCHAR(100),
    geometry GEOMETRY(POLYGON, 4326) NOT NULL,
    area_sq_m NUMERIC,
    perimeter_m NUMERIC,
    -- Additional attributes that might be in shapefiles
    lot_number VARCHAR(50),
    block_number VARCHAR(50),
    street_address VARCHAR(255),
    owner_name VARCHAR(255),
    building_type VARCHAR(100),
    construction_year INTEGER,
    -- Temporal fields for versioning
    valid_from DATE NOT NULL,
    valid_to DATE,
    source_confidence NUMERIC CHECK (source_confidence >= 0 AND source_confidence <= 1),
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Historical buildings table (with temporal fields)
CREATE TABLE buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES data_sources(id),
    building_id VARCHAR(100),
    timewalk_id VARCHAR(100) UNIQUE, -- Unique identifier linking to Unreal objects
    name TEXT,
    geometry GEOMETRY(POLYGON, 4326) NOT NULL,
    area_sq_m NUMERIC,
    height_m NUMERIC,
    floors INTEGER,
    building_type VARCHAR(100),
    style VARCHAR(100),
    construction_year INTEGER,
    demolition_year INTEGER,
    -- Ownership and design information
    owner_name VARCHAR(255),
    owner_type VARCHAR(100), -- 'individual', 'corporation', 'government', 'religious', etc.
    architect VARCHAR(255),
    architect_firm VARCHAR(255),
    -- Additional building attributes
    roof_type VARCHAR(50),
    material VARCHAR(100),
    -- Temporal fields for versioning
    valid_from DATE NOT NULL,
    valid_to DATE,
    source_confidence NUMERIC CHECK (source_confidence >= 0 AND source_confidence <= 1),
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Historical boundaries table
CREATE TABLE boundaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES data_sources(id),
    boundary_id VARCHAR(100),
    geometry GEOMETRY(POLYGON, 4326) NOT NULL,
    boundary_type VARCHAR(100),
    name VARCHAR(255),
    description TEXT,
    -- Temporal fields
    valid_from DATE NOT NULL,
    valid_to DATE,
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Media assets table (links to Supabase Storage)
CREATE TABLE media_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind media_type NOT NULL,
    storage_path TEXT NOT NULL, -- Supabase Storage path
    license TEXT,
    creator TEXT,
    capture_time TIMESTAMP WITH TIME ZONE,
    capture_geom GEOMETRY(POINT, 4326),
    -- Additional metadata
    file_size_bytes BIGINT,
    mime_type TEXT,
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Building-media linking table
CREATE TABLE building_media (
    building_id UUID REFERENCES buildings ON DELETE CASCADE,
    media_id UUID REFERENCES media_assets ON DELETE CASCADE,
    role media_role NOT NULL,
    PRIMARY KEY (building_id, media_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Parcel-media linking table
CREATE TABLE parcel_media (
    parcel_id UUID REFERENCES building_parcels ON DELETE CASCADE,
    media_id UUID REFERENCES media_assets ON DELETE CASCADE,
    role media_role NOT NULL,
    PRIMARY KEY (parcel_id, media_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Building notes table for timestamped research notes
CREATE TABLE building_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    building_id UUID REFERENCES buildings ON DELETE CASCADE,
    source_id UUID REFERENCES sources(id), -- Optional reference to source document
    researcher_name VARCHAR(255) NOT NULL,
    note_text TEXT NOT NULL,
    note_type VARCHAR(100), -- 'research', 'correction', 'question', 'confirmation', etc.
    confidence_level VARCHAR(50), -- 'high', 'medium', 'low', 'speculative'
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Raster data metadata table
CREATE TABLE raster_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id UUID REFERENCES data_sources(id),
    raster_id VARCHAR(100),
    file_path VARCHAR(500) NOT NULL,
    raster_type VARCHAR(100), -- 'dem', 'historical_map', 'satellite', etc.
    resolution_m NUMERIC,
    pixel_size_x NUMERIC,
    pixel_size_y NUMERIC,
    bounds GEOMETRY(POLYGON, 4326),
    -- Temporal fields
    valid_from DATE NOT NULL,
    valid_to DATE,
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Historical events table for temporal data
CREATE TABLE historical_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    event_date DATE,
    time_period time_period NOT NULL,
    location GEOMETRY(POINT, 4326),
    significance TEXT,
    source_id UUID REFERENCES sources(id),
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Streets table (from ChatGPT suggestions)
CREATE TABLE streets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    geometry GEOMETRY(MULTILINESTRING, 4326) NOT NULL,
    street_class VARCHAR(100),
    -- Temporal fields
    valid_from DATE NOT NULL,
    valid_to DATE,
    -- Audit fields
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_building_parcels_geometry ON building_parcels USING GIST (geometry);
CREATE INDEX idx_building_parcels_source_id ON building_parcels (source_id);
CREATE INDEX idx_building_parcels_valid_from ON building_parcels (valid_from);
CREATE INDEX idx_building_parcels_valid_to ON building_parcels (valid_to);

CREATE INDEX idx_buildings_geometry ON buildings USING GIST (geometry);
CREATE INDEX idx_buildings_source_id ON buildings (source_id);
CREATE INDEX idx_buildings_construction_year ON buildings (construction_year);
CREATE INDEX idx_buildings_valid_from ON buildings (valid_from);
CREATE INDEX idx_buildings_valid_to ON buildings (valid_to);
CREATE INDEX idx_buildings_owner_name ON buildings (owner_name);
CREATE INDEX idx_buildings_architect ON buildings (architect);
CREATE INDEX idx_buildings_timewalk_id ON buildings (timewalk_id);

CREATE INDEX idx_boundaries_geometry ON boundaries USING GIST (geometry);
CREATE INDEX idx_boundaries_source_id ON boundaries (source_id);
CREATE INDEX idx_boundaries_valid_from ON boundaries (valid_from);

CREATE INDEX idx_raster_data_bounds ON raster_data USING GIST (bounds);
CREATE INDEX idx_raster_data_source_id ON raster_data (source_id);
CREATE INDEX idx_raster_data_valid_from ON raster_data (valid_from);

CREATE INDEX idx_historical_events_location ON historical_events USING GIST (location);
CREATE INDEX idx_historical_events_time_period ON historical_events (time_period);
CREATE INDEX idx_historical_events_event_date ON historical_events (event_date);

CREATE INDEX idx_streets_geometry ON streets USING GIST (geometry);
CREATE INDEX idx_streets_valid_from ON streets (valid_from);

CREATE INDEX idx_media_assets_capture_geom ON media_assets USING GIST (capture_geom);
CREATE INDEX idx_media_assets_kind ON media_assets (kind);

CREATE INDEX idx_building_notes_building_id ON building_notes (building_id);
CREATE INDEX idx_building_notes_source_id ON building_notes (source_id);
CREATE INDEX idx_building_notes_researcher_name ON building_notes (researcher_name);
CREATE INDEX idx_building_notes_created_at ON building_notes (created_at);

-- Helper functions for authentication and roles
CREATE OR REPLACE FUNCTION is_editor() RETURNS BOOLEAN
LANGUAGE SQL STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.role IN ('editor','admin')
  );
$$;

CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN
LANGUAGE SQL STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'
  );
$$;

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers to all tables
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_sources_updated_at BEFORE UPDATE ON sources FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_data_sources_updated_at BEFORE UPDATE ON data_sources FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_building_parcels_updated_at BEFORE UPDATE ON building_parcels FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_buildings_updated_at BEFORE UPDATE ON buildings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_boundaries_updated_at BEFORE UPDATE ON boundaries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_media_assets_updated_at BEFORE UPDATE ON media_assets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_building_notes_updated_at BEFORE UPDATE ON building_notes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_raster_data_updated_at BEFORE UPDATE ON raster_data FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_historical_events_updated_at BEFORE UPDATE ON historical_events FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_streets_updated_at BEFORE UPDATE ON streets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create "current" views for temporal data
CREATE VIEW buildings_current AS
  SELECT * FROM buildings
  WHERE valid_from <= NOW()::DATE AND (valid_to IS NULL OR valid_to > NOW()::DATE);

CREATE VIEW building_parcels_current AS
  SELECT * FROM building_parcels
  WHERE valid_from <= NOW()::DATE AND (valid_to IS NULL OR valid_to > NOW()::DATE);

CREATE VIEW boundaries_current AS
  SELECT * FROM boundaries
  WHERE valid_from <= NOW()::DATE AND (valid_to IS NULL OR valid_to > NOW()::DATE);

CREATE VIEW streets_current AS
  SELECT * FROM streets
  WHERE valid_from <= NOW()::DATE AND (valid_to IS NULL OR valid_to > NOW()::DATE);

-- Enable Row Level Security on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE building_parcels ENABLE ROW LEVEL SECURITY;
ALTER TABLE buildings ENABLE ROW LEVEL SECURITY;
ALTER TABLE boundaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE building_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE parcel_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE building_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE raster_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE historical_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE streets ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "self read" ON profiles FOR SELECT
  USING (id = auth.uid() OR is_admin());
CREATE POLICY "admins write" ON profiles FOR ALL
  USING (is_admin());

-- Sources policies (public read, editors write)
CREATE POLICY "sources public read" ON sources FOR SELECT USING (true);
CREATE POLICY "sources editors write" ON sources FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "sources editors update" ON sources FOR UPDATE USING (is_editor());
CREATE POLICY "sources admins delete" ON sources FOR DELETE USING (is_admin());

-- Data sources policies
CREATE POLICY "data_sources public read" ON data_sources FOR SELECT USING (true);
CREATE POLICY "data_sources editors write" ON data_sources FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "data_sources editors update" ON data_sources FOR UPDATE USING (is_editor());
CREATE POLICY "data_sources admins delete" ON data_sources FOR DELETE USING (is_admin());

-- Building parcels policies
CREATE POLICY "building_parcels public read" ON building_parcels FOR SELECT USING (true);
CREATE POLICY "building_parcels editors write" ON building_parcels FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "building_parcels editors update" ON building_parcels FOR UPDATE USING (is_editor());
CREATE POLICY "building_parcels admins delete" ON building_parcels FOR DELETE USING (is_admin());

-- Buildings policies
CREATE POLICY "buildings public read" ON buildings FOR SELECT USING (true);
CREATE POLICY "buildings editors write" ON buildings FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "buildings editors update" ON buildings FOR UPDATE USING (is_editor());
CREATE POLICY "buildings admins delete" ON buildings FOR DELETE USING (is_admin());

-- Boundaries policies
CREATE POLICY "boundaries public read" ON boundaries FOR SELECT USING (true);
CREATE POLICY "boundaries editors write" ON boundaries FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "boundaries editors update" ON boundaries FOR UPDATE USING (is_editor());
CREATE POLICY "boundaries admins delete" ON boundaries FOR DELETE USING (is_admin());

-- Media assets policies
CREATE POLICY "media_assets public read" ON media_assets FOR SELECT USING (true);
CREATE POLICY "media_assets editors write" ON media_assets FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "media_assets editors update" ON media_assets FOR UPDATE USING (is_editor());
CREATE POLICY "media_assets admins delete" ON media_assets FOR DELETE USING (is_admin());

-- Building media policies
CREATE POLICY "building_media public read" ON building_media FOR SELECT USING (true);
CREATE POLICY "building_media editors write" ON building_media FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "building_media editors update" ON building_media FOR UPDATE USING (is_editor());
CREATE POLICY "building_media admins delete" ON building_media FOR DELETE USING (is_admin());

-- Parcel media policies
CREATE POLICY "parcel_media public read" ON parcel_media FOR SELECT USING (true);
CREATE POLICY "parcel_media editors write" ON parcel_media FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "parcel_media editors update" ON parcel_media FOR UPDATE USING (is_editor());
CREATE POLICY "parcel_media admins delete" ON parcel_media FOR DELETE USING (is_admin());

-- Building notes policies
CREATE POLICY "building_notes public read" ON building_notes FOR SELECT USING (true);
CREATE POLICY "building_notes editors write" ON building_notes FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "building_notes editors update" ON building_notes FOR UPDATE USING (is_editor());
CREATE POLICY "building_notes admins delete" ON building_notes FOR DELETE USING (is_admin());

-- Raster data policies
CREATE POLICY "raster_data public read" ON raster_data FOR SELECT USING (true);
CREATE POLICY "raster_data editors write" ON raster_data FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "raster_data editors update" ON raster_data FOR UPDATE USING (is_editor());
CREATE POLICY "raster_data admins delete" ON raster_data FOR DELETE USING (is_admin());

-- Historical events policies
CREATE POLICY "historical_events public read" ON historical_events FOR SELECT USING (true);
CREATE POLICY "historical_events editors write" ON historical_events FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "historical_events editors update" ON historical_events FOR UPDATE USING (is_editor());
CREATE POLICY "historical_events admins delete" ON historical_events FOR DELETE USING (is_admin());

-- Streets policies
CREATE POLICY "streets public read" ON streets FOR SELECT USING (true);
CREATE POLICY "streets editors write" ON streets FOR INSERT WITH CHECK (is_editor());
CREATE POLICY "streets editors update" ON streets FOR UPDATE USING (is_editor());
CREATE POLICY "streets admins delete" ON streets FOR DELETE USING (is_admin());

-- Insert initial data sources based on QGIS structure
INSERT INTO data_sources (name, description, time_period, data_type, data_category, file_path) VALUES
('Manhattan 1609', 'Historical data for Manhattan in 1609', '1609', 'vector', 'parcels', 'vector/1609/'),
('Manhattan 1660', 'Historical data for Manhattan in 1660', '1660', 'vector', 'parcels', 'vector/1660/'),
('Manhattan 1776', 'Historical building parcels for Manhattan in 1776', '1776', 'vector', 'parcels', 'vector/1776/'),
('DEM Data', 'Digital Elevation Models', '1776', 'raster', 'elevation', 'raster/DEM/'),
('Historical Maps', 'Historical map images', '1776', 'raster', 'historical', 'raster/HistoricalMaps/'),
('Boundary Masks', 'Boundary and mask files', '1776', 'vector', 'boundaries', 'vector/Masks/');

-- Add comments for documentation
COMMENT ON TABLE profiles IS 'User profiles extending Supabase auth.users with roles';
COMMENT ON TABLE sources IS 'Attribution and provenance for historical data';
COMMENT ON TABLE data_sources IS 'Metadata about data sources from QGIS project';
COMMENT ON TABLE building_parcels IS 'Historical building parcel polygons with temporal versioning';
COMMENT ON TABLE buildings IS 'Individual building geometries with temporal versioning';
COMMENT ON TABLE boundaries IS 'Administrative and geographic boundaries';
COMMENT ON TABLE media_assets IS 'Media files stored in Supabase Storage with metadata';
COMMENT ON TABLE building_media IS 'Links between buildings and media assets';
COMMENT ON TABLE parcel_media IS 'Links between parcels and media assets';
COMMENT ON TABLE building_notes IS 'Timestamped research notes and feedback for buildings';
COMMENT ON TABLE raster_data IS 'Metadata for raster files (DEMs, maps, etc.)';
COMMENT ON TABLE historical_events IS 'Temporal events and their locations';
COMMENT ON TABLE streets IS 'Street geometries with temporal versioning';

COMMENT ON COLUMN building_parcels.geometry IS 'Polygon geometry in EPSG:4326 (WGS84)';
COMMENT ON COLUMN buildings.geometry IS 'Building polygon geometry in EPSG:4326';
COMMENT ON COLUMN buildings.timewalk_id IS 'Unique identifier linking to Unreal Engine objects (e.g., TW_BLDG_001)';
COMMENT ON COLUMN buildings.owner_name IS 'Name of building owner (individual or organization)';
COMMENT ON COLUMN buildings.owner_type IS 'Type of owner: individual, corporation, government, religious, etc.';
COMMENT ON COLUMN buildings.architect IS 'Name of primary architect';
COMMENT ON COLUMN buildings.architect_firm IS 'Name of architectural firm';
COMMENT ON COLUMN building_notes.researcher_name IS 'Name of researcher who added the note';
COMMENT ON COLUMN building_notes.note_text IS 'The actual research note or feedback text';
COMMENT ON COLUMN building_notes.note_type IS 'Type of note: research, correction, question, confirmation, etc.';
COMMENT ON COLUMN building_notes.confidence_level IS 'Confidence level: high, medium, low, speculative';
COMMENT ON COLUMN boundaries.geometry IS 'Boundary polygon geometry in EPSG:4326';
COMMENT ON COLUMN historical_events.location IS 'Point location of historical event in EPSG:4326';
COMMENT ON COLUMN streets.geometry IS 'Street line geometry in EPSG:4326';
COMMENT ON COLUMN media_assets.storage_path IS 'Path to file in Supabase Storage bucket';
COMMENT ON COLUMN media_assets.capture_geom IS 'Location where media was captured';

COMMENT ON VIEW buildings_current IS 'Current buildings (valid_from <= now < valid_to)';
COMMENT ON VIEW building_parcels_current IS 'Current parcels (valid_from <= now < valid_to)';
COMMENT ON VIEW boundaries_current IS 'Current boundaries (valid_from <= now < valid_to)';
COMMENT ON VIEW streets_current IS 'Current streets (valid_from <= now < valid_to)';
