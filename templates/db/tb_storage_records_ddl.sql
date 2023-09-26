create table if not exists StorageRecords(
  context varchar(255) not null,
  id varchar(255) not null,
  expires bigint(20) default null,
  value longtext not null,
  version bigint(20) not null,
  primary key (context,id)
) DEFAULT CHARSET=utf8 COLLATE=utf8_bin;
