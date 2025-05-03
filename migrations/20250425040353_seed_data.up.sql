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

-- Tavern doors
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

-- Innkeeper
WITH new_pos AS (
  INSERT INTO positions (x,y,room_id)
  SELECT 4, 1, entity_id
  FROM names
  WHERE name='Tavern'
  RETURNING entity_id
),
new_hp AS (
  INSERT INTO hps (entity_id, hp, maxhp)
  SELECT entity_id, 10, 10
  FROM new_pos
),
new_weight AS (
  INSERT INTO weights (entity_id, weight)
  SELECT entity_id, 1
  FROM new_pos
),
new_llm AS (
  INSERT INTO llms (entity_id)
  SELECT entity_id
  FROM new_pos
)
INSERT INTO species (entity_id, species)
SELECT entity_id, 'innkeeper'
FROM new_pos;

-- Quests
INSERT INTO quests (description, species_name, species_count, giver, reward_species, reward_count)
SELECT 'Slay one snake and bring its corpse. Snakes may be found in the snake dungeon. The reward is one gold coin.', 'snake', 1, entity_id, 'gold count', 1
FROM species WHERE species='innkeeper';

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

-- Upstair
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

-- Snakes
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
),
new_weight AS (
  INSERT INTO weights (entity_id, weight)
  SELECT entity_id, 1
  FROM new_pos
),
new_monsters AS (
  INSERT INTO monsters (entity_id)
  SELECT entity_id
  FROM new_pos)
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
),
new_weight AS (
  INSERT INTO weights (entity_id, weight)
  SELECT entity_id, 1
  FROM new_pos
),
new_monsters AS (
  INSERT INTO monsters (entity_id)
  SELECT entity_id
  FROM new_pos)
INSERT INTO species (entity_id, species)
SELECT entity_id, 'snake'
FROM new_pos;

