-- Como 'Root':
CREATE DATABASE joyeria_db;

GRANT ALL PRIVILEGES ON joyeria_db.* to joyeria_user@localhost IDENTIFIED BY '666';

FLUSH PRIVILEGES;
