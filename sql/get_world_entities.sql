SELECT 
  p.entity_id "entity_id!", 
  p.x as "x!", 
  p.y as "y!", 
  p.room_id as "room_id!",
  s.species,
  c.command_type AS "command_type",
  c.x AS "command_x",
  c.y AS "command_y",
  h.hp,
  h.maxhp,
  portals.ends,
  weight
FROM positions st 
LEFT JOIN positions P ON (p.room_id=st.room_id OR p.room_id=st.entity_id)
LEFT JOIN species s ON s.entity_id=p.entity_id
LEFT JOIN commands c ON c.entity_id=p.entity_id
LEFT JOIN hps h ON h.entity_id=p.entity_id
LEFT JOIN weights w ON w.entity_id=p.entity_id
CROSS JOIN LATERAL (SELECT ARRAY_AGG(end_entity_id) ends FROM portals WHERE start_entity_id=p.entity_id) portals
WHERE st.entity_id=$1
ORDER BY p.entity_id ASC;


