GRANT SUPER ON *.* TO 'root'@'localhost' IDENTIFIED BY '{{ db.password }}';
GRANT SUPER ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY '{{ db.password }}';
GRANT SUPER ON *.* TO 'root'@'::1' IDENTIFIED BY '{{ db.password }}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;

