-- Create a function to generate a 2D BSP dungeon using recursive CTE
CREATE OR REPLACE FUNCTION generate_bsp(
    width INT,
    height INT,
    max_room_size INT DEFAULT 20,
    min_partition_size INT DEFAULT 10,
    split_threshold FLOAT DEFAULT 0.5
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
                
                -- Calculate split position, ensuring each side has at least min_partition_size
                CASE
                    WHEN p.w >= p.h THEN  -- For horizontal splits
                        min_partition_size + 
                        (random() * (p.w - 2 * min_partition_size))::INT
                    ELSE                  -- For vertical splits
                        min_partition_size + 
                        (random() * (p.h - 2 * min_partition_size))::INT
                END AS position
        ) AS split
    WHERE 
        -- Only process partitions that are large enough to split
        p.partition_type != 'leaf' AND
        p.w >= 2 * min_partition_size AND 
        p.h >= 2 * min_partition_size AND
        -- Limit recursion depth
        p.depth < 10
),
-- Mark leaf nodes and determine final partitions
leaf_partitions AS (
    SELECT
        id,
        x,
        y,
        -- Cap size at max_room_size (optional)
        LEAST(w, max_room_size) AS w,
        LEAST(h, max_room_size) AS h,
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
    max_room_size INT DEFAULT 20,
    min_partition_size INT DEFAULT 10
) RETURNS TABLE (
    room_id INT,
    template TEXT,
    id INT,
    x INT,
    y INT,
    w INT,
    h INT,
    parent_id INT
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
    SELECT * FROM generate_bsp(width, height, max_room_size, min_partition_size)
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
    -- Order by the rank to get a deterministic but random ordering
    ORDER BY rank DESC
    -- Limit to exact room count
    LIMIT CASE 
        WHEN room_count IS NULL THEN NULL
        ELSE room_count
    END
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
-- Determine which coordinates should be floor tiles (+)
floor_tiles AS (
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
),
-- Generate dungeon map directly from grid coordinates
dungeon_map AS (
    SELECT 
        g.y,
        string_agg(
            CASE 
                WHEN EXISTS (
                    SELECT 1 FROM floor_tiles f 
                    WHERE f.x = g.x AND f.y = g.y
                ) THEN '+'
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
    template,
    id,
    x,
    y,
    w,
    h,
    parent_id
FROM create_template
CROSS JOIN (
    SELECT * FROM selected_leaves
);
$$ LANGUAGE SQL;