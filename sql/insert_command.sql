INSERT INTO commands (entity_id, command_type, x, y, target) values ($1, $2, $3, $4, $5) ON CONFLICT(entity_id) DO UPDATE
SET 
  command_type=EXCLUDED.command_type,
  x=EXCLUDED.x,
  y=EXCLUDED.y,
  target=EXCLUDED.target;
