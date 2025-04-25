CREATE SEQUENCE entities_idx;
CREATE TABLE names (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  name TEXt
);

CREATE TABLE positions (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  x SMALLINT,
  y SMALLINT,
  room_id INTEGER
);

CREATE INDEX positions_btree ON positions(x,y);

CREATE TABLE species (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  species TEXT
);

CREATE TABLE commands (
  entity_id INTEGER DEFAULT nextval('entities_idx') UNIQUE,
  command_type TEXT,
  x SMALLINT,
  y SMALLINT,
  target INT
);

CREATE TABLE players (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  password TEXT
);

CREATE TABLE rooms (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  min_commands INT,
  landing_zone BOOLEAN
);

CREATE TABLE impassibles (
  entity_id INTEGER DEFAULT nextval('entities_idx')
);

CREATE TABLE hps (
  entity_id INTEGER DEFAULT nextval('entities_idx'),
  hp INT,
  maxhp INT
);

CREATE TABLE portals (
  start_entity_id INTEGER,
  end_entity_id INTEGER 
);


CREATE OR REPLACE FUNCTION create_room_template(
  room_entity_id INT,
  template TEXT
)  RETURNS VOID
AS $$
BEGIN
  WITH
  lines AS (
    SELECT 
      row_number() OVER () - 1 AS y,
      line AS line
    FROM regexp_split_to_table(template, '\n') AS line
    WHERE length(trim(line)) > 0
  ),
  tiles AS (
    SELECT 
      nextval('entities_idx') entity_id,
      x,
      y, 
      substring(line FROM x+1 FOR 1) AS character
    FROM lines, lateral generate_series(0, length(line)-1) AS x
    WHERE x < length(line) AND substring(line FROM x+1 FOR 1) != ' '
  ),
  impassibles AS (
    INSERT INTO impassibles (entity_id)
    SELECT entity_id FROM tiles WHERE character='#'
  ),
  species AS (
    INSERT INTO species (entity_id, species)
    SELECT entity_id, CASE
      WHEN character = '#' THEN 'wall'
      WHEN character = '+' THEN 'floor'
      ELSE ''
    END
    FROM tiles
  )
  INSERT INTO positions (entity_id, x, y, room_id)
  SELECT entity_id, x, y, room_entity_id
  FROM tiles;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION room_tick()
RETURNS TRIGGER AS $$
BEGIN
  WITH triggered_rooms AS (
    SELECT 
      p.room_id
    FROM 
      positions p
    LEFT JOIN positions po ON 
      po.room_id=p.room_id
    INNER JOIN players pl ON 
      pl.entity_id=po.entity_id
    LEFT JOIN commands c ON 
      c.entity_id=pl.entity_id
    LEFT JOIN rooms r ON r.entity_id=p.room_id
    WHERE p.entity_id=NEW.entity_id
    GROUP BY p.room_id, r.min_commands
    HAVING (COUNT(po.*) = COUNT(c.*)) OR (COUNT(c.*) >= r.min_commands)
  ),
  removed_commands AS (
    DELETE FROM commands
    USING positions p 
    WHERE 
      p.room_id IN (SELECT room_id FROM triggered_rooms) AND 
      commands.entity_id=p.entity_id
    RETURNING commands.*
  ),
  actioned_commands AS (
    SELECT rm.* FROM removed_commands rm
    INNER JOIN hps ON hps.hp > 0 AND hps.entity_id=rm.entity_id
  ),
  travels AS (
    UPDATE positions SET 
      x=targ_p.x,
      y=targ_p.y,
      room_id=targ_p.room_id
    FROM actioned_commands c
    INNER JOIN portals p ON p.start_entity_id=c.target
    INNER JOIN positions targ_p ON targ_p.entity_id=p.end_entity_id
    WHERE c.command_type='travel' AND positions.entity_id=c.entity_id
  ),
  picked_up AS (
    UPDATE positions SET
      x = 0,
      y = 0,
      room_id = c.entity_id
    FROM commands c
    WHERE positions.entity_id=c.target AND c.command_type='pickup'
  ),
  new_pos AS (
    UPDATE positions SET
      x = positions.x + c.x,
      y = positions.y + c.y
    FROM actioned_commands c
    WHERE 
      positions.entity_id=c.entity_id AND 
      c.command_type='move' AND 
      positions.room_id IN (SELECT room_id FROM triggered_rooms)
      AND NOT EXISTS (SELECT * FROM impassibles i INNER JOIN positions p ON p.x=positions.x+c.x AND p.y=positions.y+c.y AND p.entity_id=i.entity_id AND p.room_id=positions.room_id)
      RETURNING *
    )
  UPDATE hps 
  SET hp=hp-1
  FROM actioned_commands c
  WHERE c.target=hps.entity_id AND c.command_type='attack';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER room_tick
AFTER INSERT OR UPDATE ON commands
FOR EACH ROW
EXECUTE FUNCTION room_tick();
