SELECT ss.species "sender!", rs.species "receiver!",message "message!"
FROM messages
LEFT JOIN species ss ON ss.entity_id=messages.speaker
LEFT JOIN species rs ON rs.entity_id=messages.recipient
WHERE messages.speaker=$1 OR messages.recipient=$1
ORDER BY sent_at ASC;


