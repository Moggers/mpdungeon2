CREATE SEQUENCE entities_idx;
CREATE TABLE names (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  name TEXt
);

CREATE TABLE positions (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  x SMALLINT,
  y SMALLINT,
  room_id INTEGER
);

CREATE INDEX positions_btree ON positions(x,y);

CREATE TABLE species (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  species TEXT
);

CREATE TABLE commands (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx') UNIQUE,
  command_type TEXT,
  x SMALLINT,
  y SMALLINT,
  target INT
);

CREATE TABLE players (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  password TEXT
);

CREATE TABLE rooms (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  min_commands INT,
  landing_zone BOOLEAN
);

CREATE TABLE impassibles (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx')
);

CREATE TABLE hps (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  hp INT,
  maxhp INT
);

CREATE TABLE portals (
  start_entity_id INTEGER,
  end_entity_id INTEGER 
);

CREATE TABLE monsters (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx')
);

CREATE TABLE weights (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  weight INTEGER
);

CREATE TABLE quests (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx'),
  description TEXT,
  species_name TEXT,
  species_count INT,
  reward_species TEXT,
  reward_count INT,
  giver INTEGER
);

CREATE TABLE messages (
  speaker INTEGER,
  recipient INTEGER,
  message TEXT,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  seen_by_responder BOOLEAN DEFAULT false
);

CREATE TABLE llms (
  entity_id INTEGER PRIMARY KEY DEFAULT nextval('entities_idx')
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
  monster_attack_commands AS (
    SELECT p.entity_id::int, 'attack'::text, null::smallint, null::smallint, com.targ_entity_id::int
    FROM 
      triggered_rooms t,
      positions p,
      monsters m,
      hps h,
      LATERAL (
        SELECT hs.entity_id "targ_entity_id"
        FROM hps h 
        INNER JOIN positions hs ON hs.entity_id=h.entity_id AND hs.room_id=p.room_id
        WHERE h.entity_id != m.entity_id AND abs(hs.x - p.x) <= 1 AND abs(hs.y - p.y) <= 1
        LIMIT 1
      ) com
      WHERE p.room_id=t.room_id AND p.entity_id=m.entity_id AND h.entity_id=p.entity_id AND h.hp > 0
  ),
  monster_move_commands AS (
    SELECT p.entity_id::int, 'move'::text, gx, gy, null::int
    FROM 
      triggered_rooms t,
      positions p,
      monsters m,
      hps h,
      LATERAL (
        SELECT x,y
        FROM positions pt
        INNER JOIN hps ht ON ht.entity_id=pt.entity_id
        WHERE pt.room_id=p.room_id AND pt.entity_id != p.entity_id AND ht.hp > 0
        ORDER BY ABS(pt.x-p.x) + ABS(pt.y - p.y) ASC
        LIMIT 1
      ) targ,
      LATERAL (
        SELECT gx ,gy 
        FROM generate_series(-1,1) gx
        CROSS JOIN generate_series(-1,1) gy
        WHERE NOT EXISTS (
          SELECT 1
          FROM positions tp 
          INNER JOIN impassibles i ON i.entity_id=tp.entity_id
          WHERE tp.room_id=p.room_id AND tp.x=p.x+gx AND tp.y=p.y+gy
        )
        ORDER BY ABS(p.x+gx-targ.x) + ABS(p.y+gy-targ.y) ASC
        LIMIT 1
      ) com
    WHERE 
      p.room_id=t.room_id AND 
      p.entity_id=m.entity_id AND 
      h.entity_id=p.entity_id AND 
      h.hp > 0 AND 
      NOT EXISTS (SELECT mac.entity_id FROM monster_attack_commands mac WHERE mac.entity_id=p.entity_id)
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
    SELECT rm.* 
    FROM removed_commands rm
    INNER JOIN hps ON hps.hp > 0 AND hps.entity_id=rm.entity_id
    UNION ALL
    SELECT *
    FROM monster_attack_commands
    UNION ALL
    SELECT *
    FROM monster_move_commands
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

-- LLM STUFF
CREATE OR REPLACE FUNCTION respond_messages()
RETURNS void AS $$
BEGIN
  WITH new_message AS (
    UPDATE messages SET seen_by_responder=true
    FROM llms l
    WHERE messages.seen_by_responder=false AND messages.recipient=l.entity_id
    RETURNING *
  )
  INSERT INTO messages (speaker, recipient, message)
  SELECT m.recipient, m.speaker, prompt
  FROM new_message m
  CROSS JOIN openai.prompt(
'You are an innkeeper at the adventurers guild. Respond with a single line of dialog from the innkeeper, do not include the name at the start of the dialog.
The following quests may be given to players, do not include the ID when describing it:
' || (SELECT CONCAT('ID:' || entity_id || ' ' || description, E'\n') FROM quests) || '
The player has the following in their inventory: 
' || COALESCE(( select CONCAT(count(*) || ' ' || s.species, E'\n') from species s
INNER JOIN positions p ON p.entity_id=s.entity_id
WHERE p.room_id=m.speaker
GROUP BY s.species), 'EMPTY') || '
If a player successfully completes a quest with proof, add the control statement {QUEST_DONE:ID} to your response. Do not add any other control statements.'

, (
  SELECT STRING_AGG(species || ': ' || message, E'\n' ORDER BY sent_at ASC) || E'\n' || m.message
  FROM messages
  INNER JOIN species ON species.entity_id=messages.speaker
  WHERE 
    (messages.speaker=m.speaker AND messages.recipient=m.recipient) OR 
    (messages.recipient=m.speaker AND messages.speaker=m.recipient)
));
END;
$$ LANGUAGE plpgsql;

SELECT cron.schedule('respond_messages', '1 seconds', 'SELECT respond_messages()');
