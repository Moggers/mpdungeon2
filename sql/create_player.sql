WITH 
new_name AS (
  INSERT INTO names (name)  VALUES ($1)
  RETURNING entity_id
),
new_password AS (
  INSERT INTO players (entity_id, password)
  SELECT entity_id, $2
  FROM new_name
  RETURNING entity_id
),
default_room AS (
  SELECT entity_id FROM rooms r
  WHERE r.landing_zone IS TRUE
),
new_positions AS (
  INSERT INTO positions (entity_id, x, y, room_id)
  SELECT new_name.entity_id, 1, 1, r.entity_id
  FROM new_name, default_room r
  RETURNING positions.entity_id
),
new_hp AS (
  INSERT INTO hps (entity_id, hp, maxhp)
  SELECT new_name.entity_id, 10, 10  
  FROM new_name
),
new_species AS (
  INSERT INTO species (entity_id, species)
  SELECT entity_id, 'human'
  FROM new_name
  RETURNING entity_id
)
SELECT entity_id AS "entity_id!" FROM new_name

