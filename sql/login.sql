SELECT n.entity_id "entity_id!", p.entity_id IS NOT NULL as "logged_in!"
FROM names n 
LEFT JOIN players p ON p.entity_id=n.entity_id AND p.password=$2
WHERE n.name=$1
