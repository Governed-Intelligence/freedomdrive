-- Dev-only: create roles that Terraform creates in production Cloud SQL.
-- PostgreSQL runs scripts in /docker-entrypoint-initdb.d/ on first init only.
CREATE ROLE fs_app;
CREATE ROLE fs_migrator;
