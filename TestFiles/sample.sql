SELECT name, COUNT(*)
FROM users
WHERE note = 'it''s' -- all
GROUP BY name;
