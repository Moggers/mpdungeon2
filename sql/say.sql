INSERT INTO messages (speaker, recipient, message)
SELECT DISTINCT ON(speaker.entity_id) speaker.entity_id, recipient.entity_id, $3
FROM positions speaker
INNER JOIN species recipient ON recipient.species=$2
INNER JOIN positions p ON p.entity_id=recipient.entity_id AND p.room_id=speaker.room_id
WHERE speaker.entity_id=$1
;

