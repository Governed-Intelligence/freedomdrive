-- Dev-only: create the application role that production migrations expect.
CREATE ROLE fs_app WITH LOGIN PASSWORD 'fs_dev_password';
