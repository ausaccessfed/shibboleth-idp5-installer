create table if not exists tb_st(
  uid varchar(100) not null,
  sharedtoken varchar(50),
  primary key (uid)
) DEFAULT CHARACTER SET=utf8mb4 DEFAULT COLLATE utf8mb4_bin;

