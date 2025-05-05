-- create a function to generate a 2d bsp dungeon using recursive cte
CREATE OR REPLACE FUNCTION generate_bsp(
    width INT,
    height INT,
    max_room_size INT DEFAULT 20
) RETURNS TABLE (
    id INT,
    x INT,
    y INT,
    w INT,
    h INT,
    parent_id INT
) AS $$
WITH RECURSIVE partitions AS (
    -- Base case: start with a single partition covering the entire space
    SELECT 
        1 AS id,
        0 AS x, 
        0 AS y, 
        width AS w, 
        height AS h,
        NULL::INT AS parent_id,
        'root'::TEXT AS partition_type,
        0 AS depth
    
    UNION ALL
    
    -- Recursive case: each iteration generates both children (left/right or top/bottom)
    SELECT 
        CASE 
            WHEN child.side = 'left' THEN p.id * 2      -- Left/top child ID (even)
            ELSE p.id * 2 + 1                           -- Right/bottom child ID (odd)
        END AS id,
        -- X coordinate depends on split direction and which child
        CASE 
            WHEN split.is_horizontal AND child.side = 'left' THEN p.x
            WHEN split.is_horizontal AND child.side = 'right' THEN p.x + split.position
            ELSE p.x
        END AS x,
        -- Y coordinate depends on split direction and which child
        CASE 
            WHEN NOT split.is_horizontal AND child.side = 'left' THEN p.y
            WHEN NOT split.is_horizontal AND child.side = 'right' THEN p.y + split.position
            ELSE p.y
        END AS y,
        -- Width calculation
        CASE 
            WHEN split.is_horizontal AND child.side = 'left' THEN split.position
            WHEN split.is_horizontal AND child.side = 'right' THEN p.w - split.position
            ELSE p.w
        END AS w,
        -- Height calculation
        CASE 
            WHEN NOT split.is_horizontal AND child.side = 'left' THEN split.position
            WHEN NOT split.is_horizontal AND child.side = 'right' THEN p.h - split.position
            ELSE p.h
        END AS h,
        p.id AS parent_id,
        'child'::TEXT AS partition_type,
        p.depth + 1 AS depth
    FROM 
        -- Start with each partition
        partitions p
        -- Generate two children for each partition (left/right)
        CROSS JOIN (VALUES ('left'), ('right')) AS child(side)
        -- Calculate split position and direction for each partition
        CROSS JOIN LATERAL (
            SELECT
                -- Choose split direction based on aspect ratio
                CASE
                    WHEN p.w >= p.h THEN TRUE   -- Split horizontally if wider
                    ELSE FALSE                  -- Split vertically if taller
                END AS is_horizontal,
                
                -- Calculate split position with minimum separation of 1
                CASE
                    WHEN p.w >= p.h THEN  -- For horizontal splits
                        1 + (random() * (p.w - 2))::INT
                    ELSE                  -- For vertical splits
                        1 + (random() * (p.h - 2))::INT
                END AS position
        ) AS split
    WHERE 
        -- Continue subdividing until all rooms are smaller than max_room_size
        (p.w > max_room_size OR p.h > max_room_size)
),
-- Mark leaf nodes and determine final partitions
leaf_partitions AS (
    SELECT
        id,
        x,
        y,
        w,
        h,
        parent_id
    FROM partitions p
    WHERE
        -- A partition is a leaf if:
        -- 1. It has no children (doesn't exist as a parent in the tree)
        NOT EXISTS (SELECT 1 FROM partitions child WHERE child.parent_id = p.id)
        -- 2. And not the root partition
        AND p.parent_id IS NOT NULL
        -- 3. And has positive dimensions
        AND p.w > 0 AND p.h > 0
)
-- Return the leaf partitions (rooms)
SELECT * FROM leaf_partitions;
$$ LANGUAGE SQL VOLATILE;

-- Function to generate a dungeon using BSP and return room_id, template, and selected leaves
CREATE OR REPLACE FUNCTION generate_dungeon(
    width INT,
    height INT,
    room_count INT DEFAULT NULL,
    min_room_size INT default 3,
    max_room_size INT DEFAULT 20
) RETURNS TABLE (
    room_id INT,
    debug_output jsonb,
    template TEXT
) AS $$
WITH 
-- First create a room entity
room_entity AS (
    INSERT INTO rooms (min_commands, landing_zone)
    VALUES (1, false)
    RETURNING entity_id
),
-- Generate the BSP tree leaves
all_leaves AS (
    SELECT * FROM generate_bsp(width, height, max_room_size)
),
-- Count the number of leaves generated
leaf_count AS (
    SELECT count(*) AS count FROM all_leaves
),
-- Select a subset of random leaves if room_count is specified
selected_leaves AS (
    SELECT 
        all_leaves.*,
        -- Set a rank for randomized ordering
        CASE 
            WHEN room_count IS NULL OR room_count >= (SELECT count FROM leaf_count) THEN 0
            ELSE random() 
        END AS rank
    FROM all_leaves
    -- Only grab sufficiently sized rooms
    WHERE all_leaves.w > min_room_size AND all_leaves.h > min_room_size
    -- Order by the rank to get a deterministic but random ordering
    ORDER BY rank DESC
    -- Limit to exact room count
    LIMIT CASE 
        WHEN room_count IS NULL THEN NULL
        ELSE room_count
    END
),
-- Calculate all possible edges between rooms
edges AS (
    SELECT 
        r1.id AS id1,
        r2.id AS id2,
        ABS(r1.x - r2.x) + ABS(r1.y - r2.y) AS distance
    FROM 
        selected_leaves r1
        CROSS JOIN selected_leaves r2
    WHERE 
        r1.id < r2.id -- Avoid duplicates and self-connections
    ORDER BY 
        distance -- Sort by distance for MST algorithm
),

-- Use a simpler approach for corridor generation 
-- Create a star topology by connecting each room to a central room
corridors AS (
    -- Find a central room (using the one closest to the average position)
    WITH central_room AS (
        SELECT 
            id,
            x, y,
            ABS(x - (SELECT AVG(x) FROM selected_leaves)) + 
            ABS(y - (SELECT AVG(y) FROM selected_leaves)) AS distance_to_center
        FROM 
            selected_leaves
        ORDER BY 
            distance_to_center
        LIMIT 1
    )
    
    -- Connect each room to the central room
    SELECT 
        r.id AS id1,
        c.id AS id2,
        ABS(r.x - c.x) + ABS(r.y - c.y) AS distance
    FROM 
        selected_leaves r,
        central_room c
    WHERE 
        r.id != c.id
),
-- Get coordinates for all grid positions
grid_coords AS (
    SELECT 
        x, y
    FROM 
        generate_series(0, width-1) AS x
        CROSS JOIN
        generate_series(0, height-1) AS y
),
-- All potential dungeon tiles (including corridors)
raw_floor_tiles AS (
    -- Room tiles
    SELECT 
        g.x, g.y
    FROM 
        grid_coords g
    WHERE 
        EXISTS (
            SELECT 1 
            FROM selected_leaves r
            WHERE 
                g.x >= r.x AND 
                g.x < r.x + r.w AND
                g.y >= r.y AND 
                g.y < r.y + r.h
        )
    
    UNION
    
    -- Corridor tiles - create L-shaped corridors between connected rooms
    SELECT 
        x, y
    FROM (
        -- For each corridor, get the center points of the two rooms
        SELECT 
            r1.x + r1.w/2 AS x1,
            r1.y + r1.h/2 AS y1,
            r2.x + r2.w/2 AS x2,
            r2.y + r2.h/2 AS y2,
            c.id1, c.id2
        FROM 
            corridors c
            JOIN selected_leaves r1 ON c.id1 = r1.id
            JOIN selected_leaves r2 ON c.id2 = r2.id
    ) room_centers
    -- Generate the horizontal corridor segment
    CROSS JOIN LATERAL (
        SELECT 
            generate_series(
                LEAST(floor(x1)::int, floor(x2)::int),
                GREATEST(floor(x1)::int, floor(x2)::int)
            ) AS x,
            floor(y1)::int AS y
    ) horiz_corridor
    
    UNION
    
    -- Generate the vertical corridor segment for each corridor
    SELECT 
        x, y
    FROM (
        -- For each corridor, get the center points of the two rooms
        SELECT 
            r1.x + r1.w/2 AS x1,
            r1.y + r1.h/2 AS y1,
            r2.x + r2.w/2 AS x2,
            r2.y + r2.h/2 AS y2,
            c.id1, c.id2
        FROM 
            corridors c
            JOIN selected_leaves r1 ON c.id1 = r1.id
            JOIN selected_leaves r2 ON c.id2 = r2.id
    ) room_centers
    -- Generate the vertical corridor segment
    CROSS JOIN LATERAL (
        SELECT 
            floor(x2)::int AS x,
            generate_series(
                LEAST(floor(y1)::int, floor(y2)::int),
                GREATEST(floor(y1)::int, floor(y2)::int)
            ) AS y
    ) vert_corridor
),

-- Final floor tiles - excluding edge tiles which will become walls
floor_tiles AS (
    SELECT x, y 
    FROM raw_floor_tiles
    WHERE 
        x > 0 AND x < width - 1 AND
        y > 0 AND y < height - 1
),

-- Edge tiles (floors converted to walls)
edge_walls AS (
    SELECT x, y
    FROM raw_floor_tiles
    WHERE
        x = 0 OR x = width - 1 OR
        y = 0 OR y = height - 1
),
-- Identify regular wall tiles (adjacent to floor tiles)
wall_tiles AS (
    -- Standard walls: adjacent to floor tiles
    SELECT DISTINCT
        g.x, g.y
    FROM 
        grid_coords g
    WHERE 
        -- Tile is not a floor
        NOT EXISTS (
            SELECT 1 FROM floor_tiles f 
            WHERE f.x = g.x AND f.y = g.y
        )
        -- But is adjacent to a floor tile (including diagonals)
        AND EXISTS (
            SELECT 1 FROM floor_tiles f
            WHERE 
                (f.x BETWEEN g.x - 1 AND g.x + 1) AND
                (f.y BETWEEN g.y - 1 AND g.y + 1)
        )
    
    UNION
    
    -- Include the edge walls we identified earlier
    SELECT x, y FROM edge_walls
),

-- Generate dungeon map directly from grid coordinates
dungeon_map AS (
    SELECT 
        g.y,
        string_agg(
            CASE 
                -- Floor tiles 
                WHEN EXISTS (
                    SELECT 1 FROM floor_tiles f 
                    WHERE f.x = g.x AND f.y = g.y
                ) THEN '+'
                -- Wall tiles
                WHEN EXISTS (
                    SELECT 1 FROM wall_tiles w
                    WHERE w.x = g.x AND w.y = g.y
                ) THEN '#'
                -- Empty space
                ELSE ' '
            END,
            '' ORDER BY g.x
        ) AS row_str
    FROM grid_coords g
    GROUP BY g.y
    ORDER BY g.y
),
-- Combine all rows into a single string
dungeon_template AS (
    SELECT string_agg(row_str, E'\n') AS template
    FROM dungeon_map
),
-- Create the room template
create_template AS (
    SELECT 
        (SELECT entity_id FROM room_entity) AS room_id,
        (SELECT template FROM dungeon_template) AS template
),
-- Call create_room_template function
apply_template AS (
    SELECT create_room_template(
        (SELECT room_id FROM create_template),
        (SELECT template FROM create_template)
    )
)
-- Return room_id, template, and leaves for the caller
SELECT 
    room_id,
    jsonb_build_object(
      'corridors', (SELECT jsonb_agg(corridors.*) FROM corridors),
      'rooms', (SELECT jsonb_agg(selected_leaves.*) FROM selected_leaves),
      'template', (SELECT template FROM dungeon_template)
    ) "debug_output",
    (SELECT template FROM dungeon_template) AS template
FROM create_template
GROUP BY room_id;
$$ LANGUAGE SQL;
