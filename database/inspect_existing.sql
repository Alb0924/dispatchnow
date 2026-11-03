-- 在你自己的 MySQL 客户端执行。全程只读，不做 baseline 或结构修改。
-- 导出结果前核对选中 project01；不查询账户密码或业务联系人。
SELECT VERSION() AS mysql_version, DATABASE() AS selected_database,
       @@session.time_zone AS session_time_zone;

SELECT schema_name, default_character_set_name, default_collation_name
FROM information_schema.schemata WHERE schema_name='project01';

SELECT table_name, engine, table_collation
FROM information_schema.tables
WHERE table_schema='project01' AND table_type='BASE TABLE'
ORDER BY table_name;

SELECT table_name, ordinal_position, column_name, column_type,
       is_nullable, column_default, extra, generation_expression,
       character_set_name, collation_name
FROM information_schema.columns WHERE table_schema='project01'
ORDER BY table_name,ordinal_position;

SELECT table_name,index_name,non_unique,seq_in_index,column_name,
       sub_part,collation
FROM information_schema.statistics WHERE table_schema='project01'
ORDER BY table_name,index_name,seq_in_index;

SELECT k.table_name,k.constraint_name,k.column_name,k.ordinal_position,
       k.referenced_table_name,k.referenced_column_name,r.update_rule,r.delete_rule
FROM information_schema.key_column_usage k
JOIN information_schema.referential_constraints r
  ON r.constraint_schema=k.constraint_schema AND r.constraint_name=k.constraint_name
WHERE k.constraint_schema='project01'
ORDER BY k.table_name,k.constraint_name,k.ordinal_position;

SELECT constraint_name,check_clause FROM information_schema.check_constraints
WHERE constraint_schema='project01' ORDER BY constraint_name;

SELECT table_name FROM information_schema.tables
WHERE table_schema='project01' AND table_name='flyway_schema_history';
