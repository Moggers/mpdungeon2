-- Tavern
WITH 
new_room AS (
  INSERT INTO rooms (min_commands, landing_zone) VALUES (1, true)
  RETURNING entity_id
),
new_name AS (
  INSERT INTO names (entity_id, name)
  SELECT entity_id, 'Tavern'
  FROM new_room
  RETURNING entity_id
)
SELECT * 
FROM new_room 
CROSS JOIN create_room_template(new_room.entity_id,'
##########
#++++++++#
#++++++++#
#++++++++#
#++++++++#
#++++++++#
####++####'::text);

WITH new_species AS (
  INSERT INTO species (species) values ('door')
  RETURNING entity_id
)
INSERT INTO positions (entity_id, x,y, room_id)
SELECT entity_id, 4, 6, 1
FROM new_species;

WITH new_species AS (
  INSERT INTO species (species) values ('door')
  RETURNING entity_id
)
INSERT INTO positions (entity_id, x,y, room_id)
SELECT entity_id, 5, 6, 1
FROM new_species;

-- Test dungeon
WITH 
new_room AS (
  INSERT INTO rooms (min_commands, landing_zone) VALUES (null, false)
  RETURNING entity_id
),
new_name AS (
  INSERT INTO names (entity_id, name)
  SELECT entity_id, 'Dungeon'
  FROM new_room
  RETURNING entity_id
)
SELECT * FROM 
new_room
CROSS JOIN create_room_template(entity_id,'
##########       #####
#++++++++#       #+++#
#+++####+#       #+++#
#####++#+#########+++#
#++++++#+++++++++++++#
#++++++#+#############
#####+##+#
    #++++#
    ######
'::text);

WITH new_species AS (
  INSERT INTO species (species) values ('upstair')
  RETURNING entity_id
)
INSERT INTO positions (entity_id, x,y, room_id)
SELECT new_species.entity_id, 1, 1, n.entity_id
FROM new_species
LEFT JOIN names n ON n.name='Dungeon';

INSERT INTO portals (start_entity_id, end_entity_id)
SELECT s1.entity_id, s2.entity_id FROM species s1 
LEFT JOIN species s2 ON s2.species='upstair'
WHERE s1.species='door';

INSERT INTO portals (start_entity_id, end_entity_id)
SELECT s2.entity_id, s1.entity_id FROM species s1 
LEFT JOIN species s2 ON s2.species='upstair'
WHERE s1.species='door';


WITH new_pos AS (
  INSERT INTO positions (x,y,room_id)
  SELECT 3, 5, entity_id
  FROM names
  WHERE name='Dungeon'
  RETURNING entity_id
),
new_hp AS (
  INSERT INTO hps (entity_id, hp, maxhp)
  SELECT entity_id, 5, 5
  FROM new_pos
)
INSERT INTO species (entity_id, species)
SELECT entity_id, 'snake'
FROM new_pos;

WITH new_pos AS (
  INSERT INTO positions (x,y,room_id)
  SELECT 18, 2, entity_id
  FROM names
  WHERE name='Dungeon'
  RETURNING entity_id
),
new_hp AS (
  INSERT INTO hps (entity_id, hp, maxhp)
  SELECT entity_id, 5, 5
  FROM new_pos
)
INSERT INTO species (entity_id, species)
SELECT entity_id, 'snake'
FROM new_pos;

