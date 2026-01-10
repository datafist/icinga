-- Create IcingaDB database and user
CREATE DATABASE icingadb;
CREATE USER icingadb WITH ENCRYPTED PASSWORD 'icingadb';
GRANT ALL PRIVILEGES ON DATABASE icingadb TO icingadb;

-- Create Icinga Web 2 database and user
CREATE DATABASE icingaweb2;
CREATE USER icingaweb2 WITH ENCRYPTED PASSWORD 'icingaweb2';
GRANT ALL PRIVILEGES ON DATABASE icingaweb2 TO icingaweb2;

-- Create Icinga Director database and user
CREATE DATABASE director;
CREATE USER director WITH ENCRYPTED PASSWORD 'director';
GRANT ALL PRIVILEGES ON DATABASE director TO director;

-- Grant schema permissions
\c icingadb
GRANT ALL ON SCHEMA public TO icingadb;

\c icingaweb2
GRANT ALL ON SCHEMA public TO icingaweb2;

\c director
GRANT ALL ON SCHEMA public TO director;
