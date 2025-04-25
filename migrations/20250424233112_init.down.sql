-- Add down migration script here
DROP TABLE IF EXISTS positions;
DROP TABLE IF EXISTS names;
DROP TABLE IF EXISTS species;
DROP TABLE IF EXISTS commands;
DROP TABLE IF EXISTS players;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS impassibles;
DROP TABLE IF EXISTS hps;
DROP TABLE IF EXISTS portals;

DROP SEQUENCE "entities_idx";
