--
-- Copyright (c) 2005 Sylvain Pasche,
--               2006-2007 Anton A. Patrushev, Orkney, Inc.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


-- BEGIN;
----------------------------------------------------------
-- Draws an alpha shape around given set of points.
--
-- Last changes: 14.02.2008
----------------------------------------------------------
CREATE OR REPLACE FUNCTION pgr_pointsAsPolygon(query varchar)
       RETURNS SETOF pgr_geomResult AS
$$
DECLARE
     r record;
     path_result record;					     
     i int;							     
     q text;
     x float8[];
     y float8[];
     geom pgr_geomResult;
BEGIN
	
     i := 1;								     
     q := 'select 1 as gid, ST_GeometryFromText(''POLYGON((';
     
     FOR path_result IN EXECUTE 'select x, y from alphashape('''|| 
         query || ''')' LOOP
         x[i] = path_result.x;
         y[i] = path_result.y;
         i := i+1;
     END LOOP;

     q := q || x[1] || ' ' || y[1];
     i := 2;

     WHILE x[i] IS NOT NULL LOOP
         q := q || ', ' || x[i] || ' ' || y[i];
         i := i + 1;
     END LOOP;

    q := q || ', ' || x[1] || ' ' || y[1];
    q := q || '))'',-1) as the_geom';

    EXECUTE q INTO r;

	geom.seq  := 0;
    geom.id1  := 0;
    geom.id2  := 0;
    geom.geom := r.the_geom;
	RETURN NEXT geom;

    RETURN;
END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;


CREATE OR REPLACE FUNCTION pgr_drivingDistance(table_name varchar, x double precision, y double precision,
        distance double precision, cost varchar, reverse_cost varchar, directed boolean, has_reverse_cost boolean)
       RETURNS SETOF pgr_geomResult AS
$$
DECLARE
     q text;
     srid integer;
     r record;
     geom pgr_geomResult;
BEGIN
     
     EXECUTE 'SELECT srid FROM geometry_columns WHERE f_table_name = '''||table_name||'''' INTO r;
     srid := r.srid;
     
     RAISE NOTICE 'SRID: %', srid;

     q := 'SELECT * FROM pgr_pointsAsPolygon(''SELECT a.vertex_id::integer AS id, b.x1::double precision AS x, b.y1::double precision AS y'||
     ' FROM pgr_drivingDistance(''''''''SELECT gid AS id,source::integer,target::integer, '||cost||'::double precision AS cost, '||
     reverse_cost||'::double precision as reverse_cost FROM '||
     table_name||' WHERE ST_SetSRID(''''''''''''''''BOX3D('||
     x-distance||' '||y-distance||', '||x+distance||' '||y+distance||')''''''''''''''''::BOX3D, '||srid||') && the_geom  '''''''', (SELECT id FROM find_node_by_nearest_link_within_distance(''''''''POINT('||x||' '||y||')'''''''','||distance/10||','''''''''||table_name||''''''''')),'||
     distance||',true,true) a, (SELECT * FROM '||table_name||' WHERE ST_SetSRID(''''''''BOX3D('||
     x-distance||' '||y-distance||', '||x+distance||' '||y+distance||')''''''''::BOX3D, '||srid||')&&the_geom) b WHERE a.vertex_id = b.source'')';

     RAISE NOTICE 'Query: %', q;
     
     EXECUTE q INTO r;
     geom.seq  := r.seq;
     geom.id1  := r.id1;
     geom.id2  := r.id2;
     geom.geom := r.geom;
     RETURN NEXT geom;
     
     RETURN;

END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;



-----------------------------------------------------------------------
-- Calculates the driving distance.
--
-- A delta-sized bounding box around the start is used for data clipping.
--
-- This function differs from the pgr_drivingDistance in that the signature
-- is now similar to the shortest path delta functions and the delta is
-- passed as argument.
--
-- If you're accustomed to the shortest path delta functions, you probably
-- want to use this as the preferred way to get the driving distance.
--
-- table_name        the table name to work on
-- source_id         start id
-- distance          the max. cost
-- delta             delta for data clipping
-- directed          is graph directed
-- has_reverse_cost  use reverse_cost column
-----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION driving_distance_delta(table_name varchar, source_id integer,
	distance double precision, delta float8, directed boolean, has_reverse_cost boolean)
       RETURNS SETOF pgr_geomResult AS
$$
DECLARE
     q text;
     srid integer;
     r record;
     geom pgr_geomResult;

     source_x float8;
     source_y float8;
BEGIN

     EXECUTE 'SELECT srid FROM geometry_columns WHERE f_table_name = '''||table_name||''''  INTO r;
     srid := r.srid;


     EXECUTE 'select ST_X(ST_StartPoint(the_geom)) as source_x from ' ||
             quote_ident(table_name) || ' where source = ' ||
             source_id || ' limit 1' INTO r;
     source_x := r.source_x;


     EXECUTE 'select ST_Y(ST_StartPoint(the_geom)) as source_y from ' ||
             quote_ident(table_name) || ' where source = ' ||
             source_id || ' limit 1' INTO r;
     source_y := r.source_y;


     q := 'SELECT * FROM pgr_pointsAsPolygon(''SELECT a.vertex_id::integer AS id, b.x1::double precision AS x, b.y1::double precision AS y'||
     ' FROM pgr_drivingDistance(''''''''SELECT gid AS id,source::integer,target::integer, length::double precision AS cost ';

     IF has_reverse_cost THEN q := q || ', reverse_cost::double precision ';
     END IF;

     q := q || ' FROM '||table_name||' WHERE ST_SetSRID(''''''''''''''''BOX3D('||
     source_x-delta||' '||source_y-delta||', '||source_x+delta||' '||source_y+delta||')''''''''''''''''::BOX3D, '||srid||') && the_geom  '''''''', '||source_id||', '||
     distance||','||directed||','||has_reverse_cost||') a, (SELECT * FROM '||table_name||' WHERE ST_SetSRID(''''''''BOX3D('||
     source_x-delta||' '||source_y-delta||', '||source_x+delta||' '||source_y+delta||')''''''''::BOX3D, '||srid||')&&the_geom) b WHERE a.vertex_id = b.source'')';


     EXECUTE q INTO r;
     geom.seq  := r.seq;
     geom.id1  := r.id1;
     geom.id2  := r.id2;
     geom.geom := r.geom;
     RETURN NEXT geom;

     RETURN;

END;
$$

LANGUAGE 'plpgsql' VOLATILE STRICT;

-- COMMIT;
