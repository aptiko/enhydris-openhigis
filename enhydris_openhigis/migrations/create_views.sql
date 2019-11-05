CREATE SCHEMA IF NOT EXISTS openhigis;

SET search_path TO openhigis, public;

/* Stations */

DROP VIEW IF EXISTS stations;

CREATE VIEW stations
    AS SELECT
        g.id,
        g.name,
        g.remarks,
        gs.geom2100 AS geometry,
        gp.altitude,
        s.owner_id,
        s.is_automatic,
        s.start_date,
        s.end_date,
        s.overseer,
        s.copyright_years,
        s.copyright_holder
    FROM
        enhydris_gentity g
        INNER JOIN enhydris_gpoint gp ON gp.gentity_ptr_id = g.id
        INNER JOIN enhydris_station s ON s.gpoint_ptr_id = g.id
        INNER JOIN enhydris_openhigis_station gs ON gs.station_ptr_id = g.id;

CREATE OR REPLACE FUNCTION update_stations() RETURNS TRIGGER
AS $$
BEGIN
    UPDATE enhydris_openhigis_station SET geom2100=NEW.geometry
    WHERE station_ptr_id=OLD.id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stations_update
    INSTEAD OF UPDATE ON stations
    FOR EACH ROW EXECUTE PROCEDURE update_stations();

/* Functions common to all tables */

CREATE OR REPLACE FUNCTION insert_into_gentity(NEW ANYELEMENT) RETURNS integer
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    INSERT INTO enhydris_gentity (name, code, remarks, geom)
        VALUES (
            NEW.geographicalName,
            COALESCE(NEW.hydroId, ''),
            COALESCE(NEW.remarks, ''),
            ST_Transform(NEW.geometry, 4326)
        )
        RETURNING id INTO gentity_id;
    RETURN gentity_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_into_garea(NEW ANYELEMENT) RETURNS integer
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    gentity_id = openhigis.insert_into_gentity(NEW);
    INSERT INTO enhydris_garea (gentity_ptr_id, category_id)
        VALUES (gentity_id, 2);
    RETURN gentity_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_gentity(gentity_id INTEGER, OLD ANYELEMENT, NEW ANYELEMENT)
RETURNS void
AS $$
BEGIN
    UPDATE enhydris_gentity
        SET
            name=NEW.geographicalName,
            code=COALESCE(NEW.hydroId, ''),
            remarks=COALESCE(NEW.remarks, ''),
            geom=ST_Transform(NEW.geometry, 4326)
        WHERE id=gentity_id;
END;
$$ LANGUAGE plpgsql;

/* River basin districts */

DROP VIEW IF EXISTS RiverBasinDistricts;

CREATE VIEW RiverBasinDistricts
    AS SELECT
        rbd.imported_id AS objectId,
        g.name AS geographicalName,
        g.code AS hydroId,
        g.remarks,
        rbd.geom2100 AS geometry,
        ST_Perimeter(rbd.geom2100) / 1000 AS length_km,
        ST_Area(rbd.geom2100) / 1000000 AS area_sqkm
    FROM
        enhydris_gentity g
        INNER JOIN enhydris_openhigis_riverbasindistrict rbd
        ON rbd.garea_ptr_id = g.id;

CREATE OR REPLACE FUNCTION insert_into_RiverBasinDistricts() RETURNS TRIGGER
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    gentity_id = openhigis.insert_into_garea(NEW);
    INSERT INTO enhydris_openhigis_riverbasindistrict
        (garea_ptr_id, geom2100, imported_id)
        VALUES (gentity_id, NEW.geometry, NEW.objectId);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER RiverBasinDistricts_insert
    INSTEAD OF INSERT ON RiverBasinDistricts
    FOR EACH ROW EXECUTE PROCEDURE insert_into_RiverBasinDistricts();

CREATE OR REPLACE FUNCTION update_RiverBasinDistricts() RETURNS TRIGGER
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    SELECT garea_ptr_id INTO gentity_id FROM enhydris_openhigis_riverbasindistrict
        WHERE imported_id=OLD.objectId;
    PERFORM openhigis.update_gentity(gentity_id, OLD, NEW);
    UPDATE enhydris_openhigis_riverbasindistrict
    SET geom2100=NEW.geometry
    WHERE imported_id=OLD.objectId;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER RiverBasinDistricts_update
    INSTEAD OF UPDATE ON RiverBasinDistricts
    FOR EACH ROW EXECUTE PROCEDURE update_RiverBasinDistricts();

CREATE OR REPLACE FUNCTION delete_RiverBasinDistricts()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    SELECT garea_ptr_id INTO gentity_id FROM enhydris_openhigis_riverbasindistrict
        WHERE imported_id=OLD.objectId;
    DELETE FROM enhydris_openhigis_riverbasindistrict WHERE garea_ptr_id=gentity_id;
    DELETE FROM enhydris_garea WHERE gentity_ptr_id=gentity_id;
    DELETE FROM enhydris_gentity WHERE id=gentity_id;
    RETURN OLD;
END;
$$;

CREATE TRIGGER RiverBasinDistricts_delete
    INSTEAD OF DELETE ON RiverBasinDistricts
    FOR EACH ROW EXECUTE PROCEDURE delete_RiverBasinDistricts();

/* Drainage basins */

DROP VIEW IF EXISTS DrainageBasins;

CREATE VIEW DrainageBasins
    AS SELECT
        drb.imported_id as objectId,
        g.name AS geographicalName,
        g.code AS hydroId,
        g.last_modified AS beginLifespanVersion,
        g.remarks,
        drb.geom2100 AS geometry,
        parentbasin.imported_id AS parentBasin,
        CASE WHEN drb.man_made IS NULL THEN ''
             WHEN drb.man_made THEN 'manMade'
             ELSE 'natural'
             END AS origin,
        drb.hydro_order AS basinOrder,
        drb.hydro_order_scheme AS basinOrderScheme,
        drb.hydro_order_scope AS basinOrderScope,
        ST_Area(drb.geom2100) / 1000000 AS area,
        drb.total_area AS totalArea,
        drb.mean_slope AS meanSlope,
        drb.mean_elevation AS meanElevation
    FROM
        enhydris_gentity g
        INNER JOIN enhydris_openhigis_drainagebasin drb
            ON drb.garea_ptr_id = g.id
        LEFT JOIN enhydris_openhigis_drainagebasin parentbasin
            ON drb.parent_id = parentbasin.garea_ptr_id;

CREATE OR REPLACE FUNCTION insert_into_DrainageBasins() RETURNS TRIGGER
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    gentity_id = openhigis.insert_into_garea(NEW);
    INSERT INTO enhydris_openhigis_drainagebasin
        (garea_ptr_id, geom2100, parent_id, man_made, hydro_order,
        hydro_order_scheme, hydro_order_scope, total_area, mean_slope,
        mean_elevation, imported_id)
        VALUES (gentity_id, NEW.geometry, NEW.parentBasin,
            NEW.origin = 'manMade', COALESCE(NEW.basinOrder, ''),
            COALESCE(NEW.basinOrderScheme, ''),
            COALESCE(NEW.basinOrderScope, ''), NEW.totalArea, NEW.meanSlope,
            NEW.meanElevation, NEW.objectId
        );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER DrainageBasins_insert
    INSTEAD OF INSERT ON DrainageBasins
    FOR EACH ROW EXECUTE PROCEDURE insert_into_DrainageBasins();

CREATE OR REPLACE FUNCTION update_DrainageBasins() RETURNS TRIGGER
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    SELECT garea_ptr_id INTO gentity_id FROM enhydris_openhigis_drainagebasin
        WHERE imported_id=OLD.objectId;
    PERFORM openhigis.update_gentity(gentity_id, OLD, NEW);
    UPDATE enhydris_openhigis_drainagebasin
    SET
        geom2100=NEW.geometry,
        parent_id=NEW.parentBasin,
        man_made=(NEW.origin = 'manMade'),
        hydro_order=COALESCE(NEW.basinOrder, ''),
        hydro_order_scheme=COALESCE(NEW.basinOrderScheme, ''),
        hydro_order_scope=COALESCE(NEW.basinOrderScope, ''),
        total_area=NEW.totalArea,
        mean_slope=NEW.meanSlope,
        mean_elevation=NEW.meanElevation
        WHERE imported_id=OLD.objectId;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER DrainageBasins_update
    INSTEAD OF UPDATE ON DrainageBasins
    FOR EACH ROW EXECUTE PROCEDURE update_DrainageBasins();

CREATE OR REPLACE FUNCTION delete_DrainageBasins()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    SELECT garea_ptr_id INTO gentity_id FROM enhydris_openhigis_drainagebasin
        WHERE imported_id=OLD.objectId;
    DELETE FROM enhydris_openhigis_drainagebasin WHERE garea_ptr_id=gentity_id;
    DELETE FROM enhydris_garea WHERE gentity_ptr_id=gentity_id;
    DELETE FROM enhydris_gentity WHERE id=gentity_id;
    RETURN OLD;
END;
$$;

CREATE TRIGGER DrainageBasins_delete
    INSTEAD OF DELETE ON DrainageBasins
    FOR EACH ROW EXECUTE PROCEDURE delete_DrainageBasins();

/* River basins */

DROP VIEW IF EXISTS RiverBasins;

CREATE VIEW RiverBasins
    AS SELECT
        drb.imported_id AS objectId,
        g.name AS geographicalName,
        g.code AS hydroId,
        g.last_modified AS beginLifespanVersion,
        g.remarks,
        drb.geom2100 AS geometry,
        drb.parent_id AS parentBasin,
        CASE WHEN drb.man_made IS NULL THEN ''
             WHEN drb.man_made THEN 'manMade'
             ELSE 'natural'
             END AS origin,
        drb.hydro_order AS basinOrder,
        drb.hydro_order_scheme AS basinOrderScheme,
        drb.hydro_order_scope AS basinOrderScope,
        ST_Area(drb.geom2100) / 1000000 AS area,
        drb.total_area AS totalArea,
        drb.mean_slope AS meanSlope,
        drb.mean_elevation AS meanElevation
    FROM
        enhydris_gentity g
        INNER JOIN enhydris_openhigis_drainagebasin drb
        ON drb.garea_ptr_id = g.id
        INNER JOIN enhydris_openhigis_riverbasin rb
        ON rb.drainagebasin_ptr_id = g.id;

CREATE OR REPLACE FUNCTION insert_into_RiverBasins() RETURNS TRIGGER
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    gentity_id = openhigis.insert_into_garea(NEW);
    INSERT INTO enhydris_openhigis_drainagebasin
        (garea_ptr_id, geom2100, parent_id, man_made, hydro_order,
        hydro_order_scheme, hydro_order_scope, total_area, mean_slope,
        mean_elevation, imported_id)
        VALUES (gentity_id, NEW.geometry, NEW.parentBasin,
            NEW.origin = 'manMade', COALESCE(NEW.basinOrder, ''),
            COALESCE(NEW.basinOrderScheme, ''),
            COALESCE(NEW.basinOrderScope, ''), NEW.totalArea, NEW.meanSlope,
            NEW.meanElevation, NEW.objectId
        );
    INSERT INTO enhydris_openhigis_riverbasin(drainagebasin_ptr_id)
        VALUES (gentity_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER RiverBasins_insert
    INSTEAD OF INSERT ON RiverBasins
    FOR EACH ROW EXECUTE PROCEDURE insert_into_RiverBasins();

CREATE TRIGGER RiverBasins_update
    INSTEAD OF UPDATE ON RiverBasins
    FOR EACH ROW EXECUTE PROCEDURE update_DrainageBasins();

CREATE OR REPLACE FUNCTION delete_RiverBasins()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE gentity_id INTEGER;
BEGIN
    SELECT garea_ptr_id INTO gentity_id FROM enhydris_openhigis_drainagebasin
        WHERE imported_id=OLD.objectId;
    DELETE FROM enhydris_openhigis_riverbasin WHERE drainagebasin_ptr_id=gentity_id;
    DELETE FROM enhydris_openhigis_drainagebasin WHERE garea_ptr_id=gentity_id;
    DELETE FROM enhydris_garea WHERE gentity_ptr_id=gentity_id;
    DELETE FROM enhydris_gentity WHERE id=gentity_id;
    RETURN OLD;
END;
$$;

CREATE TRIGGER RiverBasins_delete
    INSTEAD OF DELETE ON RiverBasins
    FOR EACH ROW EXECUTE PROCEDURE delete_RiverBasins();

/* Give permissions */

GRANT USAGE ON SCHEMA openhigis TO mapserver, anton;
GRANT SELECT ON ALL TABLES IN SCHEMA openhigis TO mapserver;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA openhigis TO anton;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON
    enhydris_openhigis_riverbasin,
    enhydris_openhigis_drainagebasin,
    enhydris_openhigis_riverbasindistrict,
    enhydris_openhigis_station,
    enhydris_garea,
    enhydris_gentity
    TO anton;
