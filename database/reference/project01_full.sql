-- DispatchNow 完整数据库结构，MySQL 8.4，数据库名 project01。
-- 2026-11-03；适用于空库初始化。不删除或覆盖任何已有业务表。
-- DDL 会隐式提交；首次失败后应查明原因，不使用 --force 继续执行。
-- 使用具备建库、建表、ALTER、REFERENCES、CREATE TEMPORARY TABLES 权限的账号执行。
SET NAMES utf8mb4;
SET SESSION time_zone = '+00:00';
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,ONLY_FULL_GROUP_BY';
CREATE DATABASE IF NOT EXISTS `project01`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE `project01`;


-- 遇错必须停止；不对已有业务库补建或覆盖。临时表只存在于当前连接。
CREATE TEMPORARY TABLE `__project01_init_guard` (
  selected_database_is_project01 TINYINT NOT NULL,
  existing_table_or_view_count INT NOT NULL,
  CONSTRAINT `project01_initialization_requires_empty_database`
    CHECK (selected_database_is_project01 = 1 AND existing_table_or_view_count = 0)
);
INSERT INTO `__project01_init_guard`
SELECT IF(DATABASE() = 'project01', 1, 0), COUNT(*)
FROM information_schema.tables WHERE table_schema = DATABASE();
DROP TEMPORARY TABLE `__project01_init_guard`;
-- P0 | 配置与计费 | 服务城市与当前规则入口
CREATE TABLE `service_city` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市代码，不与外部地图供应商行政编码强耦合',
  `city_name` VARCHAR(64) NOT NULL COMMENT '城市展示名',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '该城市统一使用的坐标系',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DISABLED' COMMENT '服务开关',
  `active_pricing_rule_id` BIGINT NULL COMMENT '当前计费规则版本，发布时锁定城市行切换',
  `active_dispatch_policy_id` BIGINT NULL COMMENT '当前派单策略版本',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_service_city_city_code` (`city_code`),
  KEY `ix_service_city_city_code_active_pricing_rule_id` (`city_code`, `active_pricing_rule_id`),
  KEY `ix_service_city_city_code_active_dispatch_policy_id` (`city_code`, `active_dispatch_policy_id`),
  CONSTRAINT `ck_service_city_1` CHECK (version >= 0),
  CONSTRAINT `ck_service_city_2` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09')),
  CONSTRAINT `ck_service_city_3` CHECK (`status` IN ('ENABLED','DISABLED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='服务城市与当前规则入口';

-- P0 | 账户与骑手 | 平台账户
CREATE TABLE `app_user` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `user_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '公开用户编号',
  `mobile_cipher` VARBINARY(512) NOT NULL COMMENT '手机号密文，封装包含 nonce 与认证标签',
  `mobile_hash` BINARY(32) NOT NULL COMMENT '规范化手机号的 HMAC-SHA256，密钥与加密密钥分离',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '加密密钥版本，支持轮换',
  `password_hash` VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '密码自适应哈希，禁止明文或可逆密码',
  `nickname` VARCHAR(64) NOT NULL COMMENT '昵称',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE' COMMENT '账户状态',
  `last_login_at` DATETIME(3) NULL COMMENT '最近成功登录时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '资料并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_app_user_user_no` (`user_no`),
  UNIQUE KEY `uk_app_user_mobile_hash` (`mobile_hash`),
  CONSTRAINT `ck_app_user_1` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_app_user_2` CHECK (version >= 0),
  CONSTRAINT `ck_app_user_3` CHECK (`status` IN ('ACTIVE','DISABLED','CLOSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='平台账户';

-- P0 | 账户与骑手 | 账户角色分配
CREATE TABLE `user_role` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `user_id` BIGINT NOT NULL COMMENT '所属账户',
  `role_code` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '固定角色代码，具体权限由代码白名单映射',
  `granted_by` BIGINT NULL COMMENT '授予人；受控系统初始化可为空',
  `granted_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '授予时间',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_role_user_id_role_code` (`user_id`, `role_code`),
  KEY `ix_user_role_granted_by` (`granted_by`),
  CONSTRAINT `ck_user_role_1` CHECK (`role_code` IN ('USER','RIDER','OPS_SUPPORT','OPS_DISPATCH','OPS_FINANCE','OPS_ADMIN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='账户角色分配';

-- P0 | 账户与骑手 | 可修改的用户地址簿
CREATE TABLE `user_address` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `user_id` BIGINT NOT NULL COMMENT '地址所有者',
  `label` VARCHAR(32) NULL COMMENT '家、公司等用户标签',
  `contact_name_cipher` VARBINARY(512) NOT NULL COMMENT '联系人姓名密文',
  `phone_cipher` VARBINARY(512) NOT NULL COMMENT '联系手机号密文',
  `address_text_cipher` VARBINARY(2048) NOT NULL COMMENT '详细地址密文',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '上述密文字段的密钥版本',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `longitude` DECIMAL(10,7) NOT NULL COMMENT '经度',
  `latitude` DECIMAL(10,7) NOT NULL COMMENT '纬度',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '坐标系',
  `is_default` TINYINT NOT NULL DEFAULT 0 COMMENT '是否默认地址',
  `deleted_at` DATETIME(3) NULL COMMENT '地址簿软删除，不影响任何报价或订单快照',
  `default_owner_id` BIGINT GENERATED ALWAYS AS (CASE WHEN is_default = 1 AND deleted_at IS NULL THEN user_id ELSE NULL END) STORED COMMENT '实现每个用户至多一条有效默认地址',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_address_default_owner_id` (`default_owner_id`),
  KEY `ix_user_address_user_id_deleted_at_id` (`user_id`, `deleted_at`, `id`),
  KEY `ix_user_address_city_code` (`city_code`),
  CONSTRAINT `ck_user_address_1` CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_user_address_2` CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_user_address_3` CHECK (is_default IN (0,1)),
  CONSTRAINT `ck_user_address_4` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_user_address_5` CHECK (version >= 0),
  CONSTRAINT `ck_user_address_6` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='可修改的用户地址簿';

-- P0 | 账户与骑手 | 骑手身份、审核和车辆资料
CREATE TABLE `rider_profile` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `user_id` BIGINT NOT NULL COMMENT '一个账户最多一份骑手资料',
  `rider_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '公开骑手编号',
  `display_name` VARCHAR(64) NOT NULL COMMENT '骑手展示名',
  `real_name_cipher` VARBINARY(512) NULL COMMENT '审核所需实名信息密文',
  `crypto_key_version` SMALLINT NULL COMMENT '实名密钥版本',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `approval_state` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING' COMMENT '审核状态',
  `vehicle_type` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'E_BIKE' COMMENT '载具类型',
  `max_load_g` INT NOT NULL DEFAULT 10000 COMMENT '车辆可承载重量上限，克',
  `reviewed_by` BIGINT NULL COMMENT '审核运营账户',
  `reviewed_at` DATETIME(3) NULL COMMENT '审核时间',
  `review_note` VARCHAR(500) NULL COMMENT '审核或暂停原因',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_rider_profile_user_id` (`user_id`),
  UNIQUE KEY `uk_rider_profile_rider_no` (`rider_no`),
  KEY `ix_rider_profile_city_code_approval_state_id` (`city_code`, `approval_state`, `id`),
  KEY `ix_rider_profile_reviewed_by` (`reviewed_by`),
  CONSTRAINT `ck_rider_profile_1` CHECK (max_load_g > 0),
  CONSTRAINT `ck_rider_profile_2` CHECK (version >= 0),
  CONSTRAINT `ck_rider_profile_3` CHECK (approval_state = 'PENDING' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CONSTRAINT `ck_rider_profile_4` CHECK ((real_name_cipher IS NULL AND crypto_key_version IS NULL) OR (real_name_cipher IS NOT NULL AND crypto_key_version > 0)),
  CONSTRAINT `ck_rider_profile_5` CHECK (`approval_state` IN ('PENDING','APPROVED','REJECTED','SUSPENDED')),
  CONSTRAINT `ck_rider_profile_6` CHECK (`vehicle_type` IN ('E_BIKE','BICYCLE','MOTORCYCLE','CAR'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='骑手身份、审核和车辆资料';

-- P0 | 账户与骑手 | 骑手在线状态与事务容量
CREATE TABLE `rider_workload` (
  `rider_id` BIGINT NOT NULL COMMENT '骑手主键，一对一容量行',
  `work_state` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OFFLINE' COMMENT '是否接新单；下线不释放持货责任',
  `capacity` INT NOT NULL DEFAULT 1 COMMENT '最大有效承接数量，P0/P1 固定按配置设为 1',
  `active_count` INT NOT NULL DEFAULT 0 COMMENT '当前未结束的实际指派数量，不等于车上货物数',
  `work_state_changed_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '上下线变更时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '锁定更新和修复校验版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`rider_id`),
  CONSTRAINT `ck_rider_workload_1` CHECK (capacity > 0),
  CONSTRAINT `ck_rider_workload_2` CHECK (active_count >= 0 AND active_count <= capacity),
  CONSTRAINT `ck_rider_workload_3` CHECK (version >= 0),
  CONSTRAINT `ck_rider_workload_4` CHECK (`work_state` IN ('ONLINE','OFFLINE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='骑手在线状态与事务容量';

-- P0 | 位置 | 骑手位置会话与旧设备隔离
CREATE TABLE `rider_location_session` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `rider_id` BIGINT NOT NULL COMMENT '骑手',
  `session_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务端生成的位置会话编号',
  `auth_session_hash` BINARY(32) NOT NULL COMMENT '绑定登录会话的不可逆摘要，不存 Cookie',
  `started_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '会话开始',
  `ended_at` DATETIME(3) NULL COMMENT '被新会话替换、退出或缓存重建时撤销',
  `end_reason` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '撤销原因',
  `current_rider_id` BIGINT GENERATED ALWAYS AS (CASE WHEN ended_at IS NULL THEN rider_id ELSE NULL END) STORED COMMENT '每名骑手至多一个当前位置会话',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_rider_location_session_session_id` (`session_id`),
  UNIQUE KEY `uk_rider_location_session_rider_id_session_id` (`rider_id`, `session_id`),
  UNIQUE KEY `uk_rider_location_session_current_rider_id` (`current_rider_id`),
  KEY `ix_rider_location_session_ended_at_id` (`ended_at`, `id`),
  CONSTRAINT `ck_rider_location_session_1` CHECK (ended_at IS NULL OR ended_at >= started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='骑手位置会话与旧设备隔离';

-- P0 | 配置与计费 | 版本化服务区域
CREATE TABLE `service_area` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `area_code` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '区域业务编号',
  `area_version` BIGINT NOT NULL COMMENT '区域版本，发布后不原地改坐标',
  `area_name` VARCHAR(64) NOT NULL COMMENT '区域名',
  `polygon_json` JSON NOT NULL COMMENT 'GeoJSON Polygon 或 MultiPolygon，不包含联系人',
  `enabled` TINYINT NOT NULL DEFAULT 0 COMMENT '同区域业务编号最多启用一版',
  `active_area_code` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin GENERATED ALWAYS AS (CASE WHEN enabled = 1 THEN area_code ELSE NULL END) STORED COMMENT '当前启用版本唯一键',
  `published_by` BIGINT NULL COMMENT '发布运营',
  `published_at` DATETIME(3) NULL COMMENT '发布时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '草稿编辑版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_service_area_city_code_area_code_area_version` (`city_code`, `area_code`, `area_version`),
  UNIQUE KEY `uk_service_area_city_code_active_area_code` (`city_code`, `active_area_code`),
  UNIQUE KEY `uk_service_area_id_city_code` (`id`, `city_code`),
  KEY `ix_service_area_city_code_enabled_id` (`city_code`, `enabled`, `id`),
  KEY `ix_service_area_published_by` (`published_by`),
  CONSTRAINT `ck_service_area_1` CHECK (area_version > 0),
  CONSTRAINT `ck_service_area_2` CHECK (enabled IN (0,1)),
  CONSTRAINT `ck_service_area_3` CHECK (version >= 0),
  CONSTRAINT `ck_service_area_4` CHECK (JSON_CONTAINS_PATH(polygon_json, 'all', '$.type', '$.coordinates') = 1 AND JSON_UNQUOTE(JSON_EXTRACT(polygon_json, '$.type')) IN ('Polygon','MultiPolygon') AND JSON_TYPE(JSON_EXTRACT(polygon_json, '$.coordinates')) = 'ARRAY'),
  CONSTRAINT `ck_service_area_5` CHECK (enabled = 0 OR (published_by IS NOT NULL AND published_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='版本化服务区域';

-- P0 | 配置与计费 | 不可变发布版计费规则
CREATE TABLE `pricing_rule` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '适用城市',
  `rule_version` BIGINT NOT NULL COMMENT '城市内单调规则版本',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DRAFT' COMMENT '发布后保持快照，当前生效版由城市入口指向',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `base_fee_cent` BIGINT NOT NULL DEFAULT 1200 COMMENT '起步费，分',
  `included_distance_m` INT NOT NULL DEFAULT 3000 COMMENT '起步包含距离，米',
  `distance_step_m` INT NOT NULL DEFAULT 1000 COMMENT '超距计费步长，米',
  `distance_step_fee_cent` BIGINT NOT NULL DEFAULT 200 COMMENT '每超距步长费用，分，不足一步向上进位',
  `included_weight_g` INT NOT NULL DEFAULT 5000 COMMENT '起步包含重量，克',
  `weight_step_g` INT NOT NULL DEFAULT 1000 COMMENT '超重计费步长，克',
  `weight_step_fee_cent` BIGINT NOT NULL DEFAULT 100 COMMENT '每超重步长费用，分',
  `max_weight_g` INT NOT NULL DEFAULT 10000 COMMENT '拒绝报价的重量上限，克',
  `quote_ttl_seconds` INT NOT NULL DEFAULT 300 COMMENT '报价有效秒数',
  `rule_json` JSON NOT NULL COMMENT '附加规则与计算口径快照，不得存敏感信息',
  `effective_at` DATETIME(3) NULL COMMENT '发布计划生效时间',
  `published_by` BIGINT NULL COMMENT '发布人',
  `published_at` DATETIME(3) NULL COMMENT '发布时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '草稿并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_pricing_rule_city_code_rule_version` (`city_code`, `rule_version`),
  UNIQUE KEY `uk_pricing_rule_city_code_id` (`city_code`, `id`),
  UNIQUE KEY `uk_pricing_rule_city_code_id_rule_version` (`city_code`, `id`, `rule_version`),
  KEY `ix_pricing_rule_published_by` (`published_by`),
  CONSTRAINT `ck_pricing_rule_1` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_pricing_rule_2` CHECK (rule_version > 0),
  CONSTRAINT `ck_pricing_rule_3` CHECK (base_fee_cent >= 0 AND distance_step_fee_cent >= 0 AND weight_step_fee_cent >= 0),
  CONSTRAINT `ck_pricing_rule_4` CHECK (included_distance_m >= 0 AND distance_step_m > 0),
  CONSTRAINT `ck_pricing_rule_5` CHECK (included_weight_g >= 0 AND weight_step_g > 0 AND max_weight_g >= included_weight_g AND max_weight_g > 0),
  CONSTRAINT `ck_pricing_rule_6` CHECK (quote_ttl_seconds > 0),
  CONSTRAINT `ck_pricing_rule_7` CHECK (version >= 0),
  CONSTRAINT `ck_pricing_rule_8` CHECK (status = 'DRAFT' OR (published_by IS NOT NULL AND published_at IS NOT NULL AND effective_at IS NOT NULL)),
  CONSTRAINT `ck_pricing_rule_9` CHECK (`status` IN ('DRAFT','PUBLISHED','RETIRED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='不可变发布版计费规则';

-- P1 | 配置与计费 | 版本化派单与超时参数
CREATE TABLE `dispatch_policy` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '城市',
  `policy_version` BIGINT NOT NULL COMMENT '城市内策略版本',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DRAFT' COMMENT '发布状态',
  `dispatch_mode` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'GRAB' COMMENT '抢单或自动邀约',
  `algorithm_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PICKUP_DISTANCE_V1' COMMENT '策略标识，固定骑手编号打破平局',
  `radius_sequence_json` JSON NOT NULL COMMENT '各轮搜索半径，单位米，如 [1000,3000,5000]',
  `offer_ttl_seconds` INT NOT NULL DEFAULT 20 COMMENT '单次邀约有效期',
  `dispatch_ttl_seconds` INT NOT NULL DEFAULT 600 COMMENT '总待接单期限',
  `location_fresh_seconds` INT NOT NULL DEFAULT 30 COMMENT '新接单所需位置新鲜度',
  `location_cache_ttl_seconds` INT NOT NULL DEFAULT 120 COMMENT '热位置缓存时限',
  `max_candidates` INT NOT NULL DEFAULT 50 COMMENT '有界候选数量',
  `policy_json` JSON NOT NULL COMMENT '保留策略附加参数快照',
  `published_by` BIGINT NULL COMMENT '发布人',
  `published_at` DATETIME(3) NULL COMMENT '发布时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '草稿版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dispatch_policy_city_code_policy_version` (`city_code`, `policy_version`),
  UNIQUE KEY `uk_dispatch_policy_city_code_id` (`city_code`, `id`),
  KEY `ix_dispatch_policy_published_by` (`published_by`),
  CONSTRAINT `ck_dispatch_policy_1` CHECK (policy_version > 0),
  CONSTRAINT `ck_dispatch_policy_2` CHECK (offer_ttl_seconds > 0 AND dispatch_ttl_seconds > 0),
  CONSTRAINT `ck_dispatch_policy_3` CHECK (location_fresh_seconds > 0 AND location_cache_ttl_seconds >= location_fresh_seconds),
  CONSTRAINT `ck_dispatch_policy_4` CHECK (max_candidates BETWEEN 1 AND 1000),
  CONSTRAINT `ck_dispatch_policy_5` CHECK (JSON_TYPE(radius_sequence_json) = 'ARRAY' AND JSON_LENGTH(radius_sequence_json) > 0),
  CONSTRAINT `ck_dispatch_policy_6` CHECK (version >= 0),
  CONSTRAINT `ck_dispatch_policy_7` CHECK (status = 'DRAFT' OR (published_by IS NOT NULL AND published_at IS NOT NULL)),
  CONSTRAINT `ck_dispatch_policy_8` CHECK (`status` IN ('DRAFT','PUBLISHED','RETIRED')),
  CONSTRAINT `ck_dispatch_policy_9` CHECK (`dispatch_mode` IN ('GRAB','AUTO'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='版本化派单与超时参数';

-- P0 | 报价与订单 | 一次性报价与非敏感快照
CREATE TABLE `delivery_quote` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `quote_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '公开报价编号',
  `user_id` BIGINT NOT NULL COMMENT '报价所有者',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `pricing_rule_id` BIGINT NOT NULL COMMENT '采用的规则行，发布版不可覆盖',
  `rule_version` BIGINT NOT NULL COMMENT '展示与审计用规则版本',
  `service_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'INSTANT' COMMENT '即时或预约',
  `item_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '物品类别',
  `item_note` VARCHAR(500) NULL COMMENT '物品说明，不含联系人明文',
  `declared_weight_g` INT NOT NULL COMMENT '申报重量，克',
  `distance_m` INT NOT NULL COMMENT '取送计费距离，米',
  `distance_source` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '道路服务或明确标识的模拟距离',
  `base_fee_cent` BIGINT NOT NULL COMMENT '起步费，分',
  `distance_fee_cent` BIGINT NOT NULL COMMENT '超距费，分',
  `weight_fee_cent` BIGINT NOT NULL COMMENT '超重费，分',
  `amount_cent` BIGINT NOT NULL COMMENT '原始报价总额，分',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `snapshot_json` JSON NOT NULL COMMENT '费率、进位、地图来源与预约输入；联系人在 quote_address 加密保存',
  `request_hash` BINARY(32) NOT NULL COMMENT '对规范化报价输入计算的摘要',
  `expires_at` DATETIME(3) NOT NULL COMMENT '到达该时间即拒绝消费',
  `consumed_order_id` BIGINT NULL COMMENT '报价被哪张订单消费，与订单创建同事务写入',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '消费竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_delivery_quote_quote_no` (`quote_no`),
  UNIQUE KEY `uk_delivery_quote_consumed_order_id` (`consumed_order_id`),
  UNIQUE KEY `uk_delivery_quote_id_city_code` (`id`, `city_code`),
  UNIQUE KEY `uk_delivery_quote_id_user_id_city_code` (`id`, `user_id`, `city_code`),
  KEY `ix_delivery_quote_user_id_created_at_id` (`user_id`, `created_at`, `id`),
  KEY `ix_delivery_quote_expires_at_id` (`expires_at`, `id`),
  KEY `ix_delivery_quote_city_code_pricing_rule_id_rule_version` (`city_code`, `pricing_rule_id`, `rule_version`),
  KEY `ix_delivery_quote_consumed_order_id_id` (`consumed_order_id`, `id`),
  CONSTRAINT `ck_delivery_quote_1` CHECK (declared_weight_g > 0 AND distance_m >= 0),
  CONSTRAINT `ck_delivery_quote_2` CHECK (base_fee_cent >= 0 AND distance_fee_cent >= 0 AND weight_fee_cent >= 0),
  CONSTRAINT `ck_delivery_quote_3` CHECK (amount_cent > 0 AND amount_cent = base_fee_cent + distance_fee_cent + weight_fee_cent),
  CONSTRAINT `ck_delivery_quote_4` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_delivery_quote_5` CHECK (expires_at > created_at),
  CONSTRAINT `ck_delivery_quote_6` CHECK (version >= 0),
  CONSTRAINT `ck_delivery_quote_7` CHECK (`service_type` IN ('INSTANT','SCHEDULED')),
  CONSTRAINT `ck_delivery_quote_8` CHECK (`distance_source` IN ('MAP_ROAD','MOCK_MATRIX','MOCK_ESTIMATE'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='一次性报价与非敏感快照';

-- P0 | 报价与订单 | 报价绑定的两端地址快照
CREATE TABLE `quote_address` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `quote_id` BIGINT NOT NULL COMMENT '所属报价',
  `address_role` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '取件或送件地址角色',
  `contact_name_cipher` VARBINARY(512) NOT NULL COMMENT '联系人姓名密文',
  `phone_cipher` VARBINARY(512) NOT NULL COMMENT '联系手机号密文',
  `address_text_cipher` VARBINARY(2048) NOT NULL COMMENT '详细地址密文',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '密钥版本',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `service_area_id` BIGINT NOT NULL COMMENT '通过范围校验时采用的区域版本',
  `longitude` DECIMAL(10,7) NOT NULL COMMENT '经度',
  `latitude` DECIMAL(10,7) NOT NULL COMMENT '纬度',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '坐标系',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_quote_address_quote_id_address_role` (`quote_id`, `address_role`),
  KEY `ix_quote_address_quote_id_city_code` (`quote_id`, `city_code`),
  KEY `ix_quote_address_service_area_id_city_code` (`service_area_id`, `city_code`),
  CONSTRAINT `ck_quote_address_1` CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_quote_address_2` CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_quote_address_3` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_quote_address_4` CHECK (`address_role` IN ('PICKUP','DROPOFF')),
  CONSTRAINT `ck_quote_address_5` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='报价绑定的两端地址快照';

-- P3 | 外部协同 | 外部系统身份与付费授权
CREATE TABLE `external_client` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `client_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '调用方编号',
  `source_system` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定来源代码，不得使用 APP',
  `owner_user_id` BIGINT NOT NULL COMMENT '该来源订单归属的平台账户，不能由请求伪造',
  `display_name` VARCHAR(80) NOT NULL COMMENT '调用方名称',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DISABLED' COMMENT '启用状态',
  `sign_algorithm` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'HMAC_SHA256' COMMENT '请求与回调签名算法',
  `secret_cipher` VARBINARY(1024) NOT NULL COMMENT '接口密钥密文，不进入业务 JSON',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '密钥版本',
  `allow_source_paid` TINYINT NOT NULL DEFAULT 0 COMMENT '是否获授权声明运费由来源承担',
  `callback_url` VARCHAR(1000) NULL COMMENT '经审核的 HTTPS 回调地址',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '授权版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_external_client_client_no` (`client_no`),
  UNIQUE KEY `uk_external_client_source_system` (`source_system`),
  UNIQUE KEY `uk_external_client_id_source_system_owner_user_id` (`id`, `source_system`, `owner_user_id`),
  KEY `ix_external_client_owner_user_id` (`owner_user_id`),
  CONSTRAINT `ck_external_client_1` CHECK (source_system <> 'APP'),
  CONSTRAINT `ck_external_client_2` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_external_client_3` CHECK (allow_source_paid IN (0,1)),
  CONSTRAINT `ck_external_client_4` CHECK (version >= 0),
  CONSTRAINT `ck_external_client_5` CHECK (`status` IN ('ENABLED','DISABLED')),
  CONSTRAINT `ck_external_client_6` CHECK (`sign_algorithm` IN ('HMAC_SHA256'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='外部系统身份与付费授权';

-- P0+P2/P3字段 | 报价与订单 | 配送聚合根与当前执行权
CREATE TABLE `delivery_order` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '公开配送单号',
  `owner_user_id` BIGINT NOT NULL COMMENT '下单人，收件人不是订单所有者',
  `quote_id` BIGINT NOT NULL COMMENT '一次性报价；一个报价最多对应一单',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `service_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'INSTANT' COMMENT '即时或预约',
  `item_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '下单时物品类别快照',
  `item_note` VARCHAR(500) NULL COMMENT '下单时物品说明快照',
  `declared_weight_g` INT NOT NULL COMMENT '原始报价重量，克',
  `actual_weight_g` INT NULL COMMENT '经确认的实际重量，克',
  `distance_m` INT NOT NULL COMMENT '下单计费距离，米',
  `distance_source` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '距离来源',
  `pricing_snapshot_json` JSON NOT NULL COMMENT '原报价规则和费用组成，不含联系人明文',
  `order_state` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'WAIT_PAYMENT' COMMENT '配送主状态，支付退款另表管理',
  `fulfillment_hold` TINYINT NOT NULL DEFAULT 0 COMMENT '冻结普通履约推进，保留持货与容量责任',
  `hold_reason` VARCHAR(500) NULL COMMENT '冻结原因',
  `dispatch_mode` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'GRAB' COMMENT '抢单或自动邀约',
  `dispatch_policy_id` BIGINT NULL COMMENT '启动派单时采用的策略版本',
  `dispatch_policy_snapshot` JSON NULL COMMENT '本单的派单参数快照',
  `dispatch_round` BIGINT NOT NULL DEFAULT 0 COMMENT '派单轮次',
  `assignment_epoch` BIGINT NOT NULL DEFAULT 0 COMMENT '执行代次，撤销和新承接时递增',
  `active_assignment_id` BIGINT NULL COMMENT '当前有效指派，结束后清空；历史不会删除',
  `total_amount_cent` BIGINT NOT NULL COMMENT '原报价配送费，分；补款另表，不覆盖原报价',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `fee_payer` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PAY_BY_USER' COMMENT '运费承担方，与商品支付无关',
  `fee_state` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'UNPAID' COMMENT '本单运费条件是否已满足',
  `fee_satisfied_at` DATETIME(3) NULL COMMENT '平台支付或来源授权完成的时间',
  `paid_payment_id` BIGINT NULL COMMENT '被本订单接受的原运费支付；来源承担时为空',
  `paid_at` DATETIME(3) NULL COMMENT '平台确认原运费收款时间；来源授权不能伪造该字段',
  `pay_expire_at` DATETIME(3) NOT NULL COMMENT '支付截止',
  `dispatch_deadline_at` DATETIME(3) NULL COMMENT '总接单截止',
  `pickup_window_start_at` DATETIME(3) NULL COMMENT 'P2 预约取件窗口起点',
  `pickup_window_end_at` DATETIME(3) NULL COMMENT 'P2 预约取件窗口终点',
  `schedule_dispatch_at` DATETIME(3) NULL COMMENT 'P2 开始派单的计划时间',
  `cancel_deadline_at` DATETIME(3) NULL COMMENT 'P2 预约可取消截止',
  `delivery_deadline_at` DATETIME(3) NULL COMMENT '承诺送达期限，与预约取件窗口不同',
  `picked_up_at` DATETIME(3) NULL COMMENT '真实核验取件时间',
  `delivered_at` DATETIME(3) NULL COMMENT '真实核验送达时间',
  `return_started_at` DATETIME(3) NULL COMMENT '进入退回中时间',
  `returned_at` DATETIME(3) NULL COMMENT '退回交接确认时间',
  `ended_at` DATETIME(3) NULL COMMENT '配送终结时间，与退款完成时间不同',
  `end_reason` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '取消、关闭等终结原因',
  `source_client_id` BIGINT NULL COMMENT '外部来源身份；原生下单为空',
  `source_system` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'APP' COMMENT '原生来源 APP 或获授权外部系统代码',
  `source_order_no` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '外部来源单号；原生下单必须为空',
  `source_authorization_snapshot` JSON NULL COMMENT '来源承担运费时冻结的身份版本与授权依据，不含密钥',
  `source_fee_reference` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '来源承担运费的授权/核对参考号',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '聚合单调版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_delivery_order_order_no` (`order_no`),
  UNIQUE KEY `uk_delivery_order_quote_id` (`quote_id`),
  UNIQUE KEY `uk_delivery_order_source_system_source_order_no` (`source_system`, `source_order_no`),
  UNIQUE KEY `uk_delivery_order_id_quote_id` (`id`, `quote_id`),
  UNIQUE KEY `uk_delivery_order_id_city_code` (`id`, `city_code`),
  UNIQUE KEY `uk_delivery_order_id_owner_user_id` (`id`, `owner_user_id`),
  UNIQUE KEY `uk_delivery_order_source_client_id_id_source_order_no` (`source_client_id`, `id`, `source_order_no`),
  UNIQUE KEY `uk_delivery_order_source_client_id_id` (`source_client_id`, `id`),
  KEY `ix_delivery_order_owner_user_id_created_at_id` (`owner_user_id`, `created_at`, `id`),
  KEY `ix_delivery_order_owner_user_id_order_state_created_at_id` (`owner_user_id`, `order_state`, `created_at`, `id`),
  KEY `ix_delivery_order_city_code_order_state_created_at_id` (`city_code`, `order_state`, `created_at`, `id`),
  KEY `ix_delivery_order_order_state_pay_expire_at_id` (`order_state`, `pay_expire_at`, `id`),
  KEY `ix_delivery_order_order_state_dispatch_deadline_at_id` (`order_state`, `dispatch_deadline_at`, `id`),
  KEY `ix_delivery_order_order_state_schedule_dispatch_at_id` (`order_state`, `schedule_dispatch_at`, `id`),
  KEY `ix_delivery_order_quote_id_owner_user_id_city_code` (`quote_id`, `owner_user_id`, `city_code`),
  KEY `ix_delivery_order_city_code_dispatch_policy_id` (`city_code`, `dispatch_policy_id`),
  KEY `ix_delivery_order_source_client_id_source_system_owner_user_id` (`source_client_id`, `source_system`, `owner_user_id`),
  KEY `ix_delivery_order_id_active_assignment_id_assignment_epoch` (`id`, `active_assignment_id`, `assignment_epoch`),
  KEY `ix_delivery_order_id_paid_payment_id` (`id`, `paid_payment_id`),
  CONSTRAINT `ck_delivery_order_1` CHECK (declared_weight_g > 0 AND (actual_weight_g IS NULL OR actual_weight_g > 0)),
  CONSTRAINT `ck_delivery_order_2` CHECK (distance_m >= 0),
  CONSTRAINT `ck_delivery_order_3` CHECK (total_amount_cent > 0),
  CONSTRAINT `ck_delivery_order_4` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_delivery_order_5` CHECK (fulfillment_hold IN (0,1)),
  CONSTRAINT `ck_delivery_order_6` CHECK (fulfillment_hold = 0 OR hold_reason IS NOT NULL),
  CONSTRAINT `ck_delivery_order_7` CHECK (dispatch_round >= 0 AND assignment_epoch >= 0 AND version >= 0),
  CONSTRAINT `ck_delivery_order_8` CHECK ((order_state IN ('WAIT_PICKUP','DELIVERING','RETURNING') AND active_assignment_id IS NOT NULL AND assignment_epoch > 0) OR (order_state NOT IN ('WAIT_PICKUP','DELIVERING','RETURNING') AND active_assignment_id IS NULL)),
  CONSTRAINT `ck_delivery_order_9` CHECK ((fee_state = 'UNPAID' AND fee_satisfied_at IS NULL) OR (fee_state = 'SATISFIED' AND fee_satisfied_at IS NOT NULL)),
  CONSTRAINT `ck_delivery_order_10` CHECK (order_state IN ('WAIT_PAYMENT','CANCELLED','CLOSED') OR fee_state = 'SATISFIED'),
  CONSTRAINT `ck_delivery_order_11` CHECK ((fee_payer = 'PAID_BY_SOURCE' AND source_client_id IS NOT NULL AND source_fee_reference IS NOT NULL AND paid_payment_id IS NULL AND paid_at IS NULL) OR fee_payer = 'PAY_BY_USER'),
  CONSTRAINT `ck_delivery_order_12` CHECK ((source_client_id IS NULL AND source_system = 'APP' AND source_order_no IS NULL) OR (source_client_id IS NOT NULL AND source_system <> 'APP' AND source_order_no IS NOT NULL)),
  CONSTRAINT `ck_delivery_order_13` CHECK ((service_type = 'INSTANT' AND pickup_window_start_at IS NULL AND pickup_window_end_at IS NULL AND schedule_dispatch_at IS NULL AND cancel_deadline_at IS NULL) OR (service_type = 'SCHEDULED' AND pickup_window_start_at IS NOT NULL AND pickup_window_end_at IS NOT NULL AND schedule_dispatch_at IS NOT NULL AND cancel_deadline_at IS NOT NULL AND pickup_window_start_at < pickup_window_end_at AND schedule_dispatch_at <= pickup_window_start_at AND cancel_deadline_at <= pickup_window_start_at)),
  CONSTRAINT `ck_delivery_order_14` CHECK (order_state <> 'WAIT_SCHEDULE' OR service_type = 'SCHEDULED'),
  CONSTRAINT `ck_delivery_order_15` CHECK (order_state NOT IN ('DELIVERING','RETURNING','COMPLETED','RETURNED') OR picked_up_at IS NOT NULL),
  CONSTRAINT `ck_delivery_order_16` CHECK (order_state <> 'COMPLETED' OR delivered_at IS NOT NULL),
  CONSTRAINT `ck_delivery_order_17` CHECK (order_state NOT IN ('RETURNING','RETURNED') OR return_started_at IS NOT NULL),
  CONSTRAINT `ck_delivery_order_18` CHECK (order_state <> 'RETURNED' OR returned_at IS NOT NULL),
  CONSTRAINT `ck_delivery_order_19` CHECK ((order_state IN ('COMPLETED','RETURNED','CANCELLED','CLOSED') AND ended_at IS NOT NULL) OR (order_state NOT IN ('COMPLETED','RETURNED','CANCELLED','CLOSED') AND ended_at IS NULL)),
  CONSTRAINT `ck_delivery_order_20` CHECK (pay_expire_at > created_at),
  CONSTRAINT `ck_delivery_order_21` CHECK (`service_type` IN ('INSTANT','SCHEDULED')),
  CONSTRAINT `ck_delivery_order_22` CHECK (`distance_source` IN ('MAP_ROAD','MOCK_MATRIX','MOCK_ESTIMATE')),
  CONSTRAINT `ck_delivery_order_23` CHECK (`order_state` IN ('WAIT_PAYMENT','WAIT_SCHEDULE','WAIT_ASSIGN','WAIT_PICKUP','DELIVERING','RETURNING','COMPLETED','RETURNED','CANCELLED','CLOSED')),
  CONSTRAINT `ck_delivery_order_24` CHECK (`dispatch_mode` IN ('GRAB','AUTO')),
  CONSTRAINT `ck_delivery_order_25` CHECK (`fee_payer` IN ('PAY_BY_USER','PAID_BY_SOURCE')),
  CONSTRAINT `ck_delivery_order_26` CHECK (`fee_state` IN ('UNPAID','SATISFIED')),
  CONSTRAINT `ck_delivery_order_27` CHECK (fee_payer <> 'PAID_BY_SOURCE' OR source_authorization_snapshot IS NOT NULL),
  CONSTRAINT `ck_delivery_order_28` CHECK (fee_payer <> 'PAY_BY_USER' OR fee_state <> 'SATISFIED' OR (paid_payment_id IS NOT NULL AND paid_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='配送聚合根与当前执行权';

-- P0 | 报价与订单 | 从报价复制的订单地址快照
CREATE TABLE `order_address` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `address_role` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '取件或送件地址角色',
  `contact_name_cipher` VARBINARY(512) NOT NULL COMMENT '联系人姓名密文',
  `phone_cipher` VARBINARY(512) NOT NULL COMMENT '联系手机号密文',
  `address_text_cipher` VARBINARY(2048) NOT NULL COMMENT '详细地址密文',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '密钥版本',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务城市',
  `service_area_id` BIGINT NOT NULL COMMENT '通过范围校验时采用的区域版本',
  `longitude` DECIMAL(10,7) NOT NULL COMMENT '经度',
  `latitude` DECIMAL(10,7) NOT NULL COMMENT '纬度',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '坐标系',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_address_order_id_address_role` (`order_id`, `address_role`),
  KEY `ix_order_address_order_id_city_code` (`order_id`, `city_code`),
  KEY `ix_order_address_service_area_id_city_code` (`service_area_id`, `city_code`),
  CONSTRAINT `ck_order_address_1` CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_order_address_2` CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_order_address_3` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_order_address_4` CHECK (`address_role` IN ('PICKUP','DROPOFF')),
  CONSTRAINT `ck_order_address_5` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='从报价复制的订单地址快照';

-- P0 | 履约与派单 | 每次实际骑手承接及持货责任
CREATE TABLE `delivery_assignment` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `rider_id` BIGINT NOT NULL COMMENT '承担履约责任的骑手',
  `epoch` BIGINT NOT NULL COMMENT '本次执行代次',
  `dispatch_round` BIGINT NOT NULL COMMENT '承接时的派单轮次',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE' COMMENT '有效、解除、送达或退回结束',
  `accepted_at` DATETIME(3) NOT NULL COMMENT '承接确认',
  `arrived_pickup_at` DATETIME(3) NULL COMMENT '到达取件点，不等于已经取件',
  `ended_at` DATETIME(3) NULL COMMENT '本次承接结束',
  `end_reason` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '解除、交接、送达、退回等原因',
  `active_order_id` BIGINT GENERATED ALWAYS AS (CASE WHEN status = 'ACTIVE' THEN order_id ELSE NULL END) STORED COMMENT '数据库保证每单最多一个 ACTIVE 历史行',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '执行记录并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_delivery_assignment_order_id_epoch` (`order_id`, `epoch`),
  UNIQUE KEY `uk_delivery_assignment_active_order_id` (`active_order_id`),
  UNIQUE KEY `uk_delivery_assignment_order_id_id_epoch` (`order_id`, `id`, `epoch`),
  UNIQUE KEY `uk_delivery_assignment_order_id_id` (`order_id`, `id`),
  UNIQUE KEY `uk_delivery_assignment_order_id_id_rider_id` (`order_id`, `id`, `rider_id`),
  UNIQUE KEY `uk_delivery_assignment_order_id_id_rider_id_epoch` (`order_id`, `id`, `rider_id`, `epoch`),
  KEY `ix_delivery_assignment_rider_id_status_accepted_at_id` (`rider_id`, `status`, `accepted_at`, `id`),
  KEY `ix_delivery_assignment_order_id_accepted_at_id` (`order_id`, `accepted_at`, `id`),
  CONSTRAINT `ck_delivery_assignment_1` CHECK (epoch > 0 AND dispatch_round > 0 AND version >= 0),
  CONSTRAINT `ck_delivery_assignment_2` CHECK ((status = 'ACTIVE' AND ended_at IS NULL) OR (status <> 'ACTIVE' AND ended_at IS NOT NULL AND end_reason IS NOT NULL)),
  CONSTRAINT `ck_delivery_assignment_3` CHECK (ended_at IS NULL OR ended_at >= accepted_at),
  CONSTRAINT `ck_delivery_assignment_4` CHECK (`status` IN ('ACTIVE','RELEASED','COMPLETED','RETURNED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='每次实际骑手承接及持货责任';

-- P1 | 履约与派单 | 派单候选、算法与参数证据
CREATE TABLE `dispatch_decision` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `dispatch_round` BIGINT NOT NULL COMMENT '派单轮次',
  `decision_seq` INT NOT NULL COMMENT '同一轮的第几次候选选择',
  `policy_id` BIGINT NOT NULL COMMENT '策略版本',
  `algorithm_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '算法和实现版本',
  `search_radius_m` INT NOT NULL COMMENT '本次召回半径',
  `candidate_snapshot_json` JSON NOT NULL COMMENT '有界候选及过滤/排序结果，不含完整手机号或地址',
  `policy_snapshot_json` JSON NOT NULL COMMENT '实际采用的参数，避免配置变更后无法复现',
  `selected_rider_id` BIGINT NULL COMMENT '没有可行候选时为空',
  `outcome` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '已选择、无候选、版本失效或拒绝',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '请求链路标识',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dispatch_decision_order_id_dispatch_round_decision_seq` (`order_id`, `dispatch_round`, `decision_seq`),
  UNIQUE KEY `uk_dispatch_decision_order_id_dispatch_round_id` (`order_id`, `dispatch_round`, `id`),
  KEY `ix_dispatch_decision_policy_id` (`policy_id`),
  KEY `ix_dispatch_decision_selected_rider_id` (`selected_rider_id`),
  CONSTRAINT `ck_dispatch_decision_1` CHECK (dispatch_round > 0 AND decision_seq > 0 AND search_radius_m > 0),
  CONSTRAINT `ck_dispatch_decision_2` CHECK (outcome <> 'SELECTED' OR selected_rider_id IS NOT NULL),
  CONSTRAINT `ck_dispatch_decision_3` CHECK (`outcome` IN ('SELECTED','NO_CANDIDATE','STALE','REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='派单候选、算法与参数证据';

-- P1 | 履约与派单 | 自动派单邀约
CREATE TABLE `dispatch_offer` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `dispatch_round` BIGINT NOT NULL COMMENT '邀约所属轮次',
  `rider_id` BIGINT NOT NULL COMMENT '目标骑手',
  `decision_id` BIGINT NULL COMMENT '候选决策记录',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING' COMMENT '邀约状态',
  `deadline_at` DATETIME(3) NOT NULL COMMENT '过期时刻，接受时必须重新校验',
  `responded_at` DATETIME(3) NULL COMMENT '接受或拒绝时间',
  `closed_at` DATETIME(3) NULL COMMENT '邀约关闭时间',
  `reason` VARCHAR(300) NULL COMMENT '拒绝、撤销或过期原因',
  `pending_order_id` BIGINT GENERATED ALWAYS AS (CASE WHEN status = 'PENDING' THEN order_id ELSE NULL END) STORED COMMENT '逐一邀约模式下每单最多一条待响应邀约',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '邀约竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_dispatch_offer_order_id_dispatch_round_rider_id` (`order_id`, `dispatch_round`, `rider_id`),
  UNIQUE KEY `uk_dispatch_offer_pending_order_id` (`pending_order_id`),
  KEY `ix_dispatch_offer_status_deadline_at_id` (`status`, `deadline_at`, `id`),
  KEY `ix_dispatch_offer_rider_id_status_deadline_at_id` (`rider_id`, `status`, `deadline_at`, `id`),
  KEY `ix_dispatch_offer_order_id_dispatch_round_decision_id` (`order_id`, `dispatch_round`, `decision_id`),
  CONSTRAINT `ck_dispatch_offer_1` CHECK (dispatch_round > 0 AND version >= 0),
  CONSTRAINT `ck_dispatch_offer_2` CHECK (deadline_at > created_at),
  CONSTRAINT `ck_dispatch_offer_3` CHECK ((status = 'PENDING' AND closed_at IS NULL) OR (status <> 'PENDING' AND closed_at IS NOT NULL)),
  CONSTRAINT `ck_dispatch_offer_4` CHECK (status NOT IN ('ACCEPTED','REJECTED') OR responded_at IS NOT NULL),
  CONSTRAINT `ck_dispatch_offer_5` CHECK (`status` IN ('PENDING','ACCEPTED','REJECTED','EXPIRED','REVOKED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='自动派单邀约';

-- P0 | 履约与派单 | 订单版本变更与状态日志
CREATE TABLE `order_status_log` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `order_version` BIGINT NOT NULL COMMENT '变更完成后的聚合版本',
  `from_state` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '创建时为空',
  `to_state` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '变更后主状态；冻结等命令可与原状态相同',
  `action` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '本次命令类型',
  `operator_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '操作者身份类别',
  `operator_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '用户、系统任务或来源身份编号',
  `reason` VARCHAR(500) NULL COMMENT '原因',
  `assignment_id` BIGINT NULL COMMENT '关联的历史指派',
  `assignment_epoch` BIGINT NOT NULL DEFAULT 0 COMMENT '变更后的执行代次',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `occurred_at` DATETIME(3) NOT NULL COMMENT '业务变更时间',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_status_log_order_id_order_version` (`order_id`, `order_version`),
  KEY `ix_order_status_log_occurred_at_id` (`occurred_at`, `id`),
  KEY `ix_order_status_log_order_id_assignment_id` (`order_id`, `assignment_id`),
  CONSTRAINT `ck_order_status_log_1` CHECK (order_version >= 0 AND assignment_epoch >= 0),
  CONSTRAINT `ck_order_status_log_2` CHECK (`operator_type` IN ('USER','RIDER','OPS','SYSTEM','EXTERNAL')),
  CONSTRAINT `ck_order_status_log_3` CHECK (from_state IS NULL OR from_state IN ('WAIT_PAYMENT','WAIT_SCHEDULE','WAIT_ASSIGN','WAIT_PICKUP','DELIVERING','RETURNING','COMPLETED','RETURNED','CANCELLED','CLOSED')),
  CONSTRAINT `ck_order_status_log_4` CHECK (to_state IN ('WAIT_PAYMENT','WAIT_SCHEDULE','WAIT_ASSIGN','WAIT_PICKUP','DELIVERING','RETURNING','COMPLETED','RETURNED','CANCELLED','CLOSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='订单版本变更与状态日志';

-- P0 | 异常与交接 | 取件后退回申请与审批
CREATE TABLE `order_return_request` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `request_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '退回申请号',
  `requested_by` BIGINT NOT NULL COMMENT '下单用户或授权运营',
  `reason` VARCHAR(500) NOT NULL COMMENT '退回原因',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING' COMMENT '进入 RETURNING 后不可普通撤销',
  `reviewed_by` BIGINT NULL COMMENT '处理运营',
  `reviewed_at` DATETIME(3) NULL COMMENT '审批时间',
  `review_note` VARCHAR(500) NULL COMMENT '处理意见',
  `withdrawn_at` DATETIME(3) NULL COMMENT '主状态变更前撤销时间',
  `completed_at` DATETIME(3) NULL COMMENT '退回交接完成',
  `open_order_id` BIGINT GENERATED ALWAYS AS (CASE WHEN status IN ('PENDING','APPROVED') THEN order_id ELSE NULL END) STORED COMMENT '同单最多一个未结束的退回请求',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_return_request_request_no` (`request_no`),
  UNIQUE KEY `uk_order_return_request_open_order_id` (`open_order_id`),
  UNIQUE KEY `uk_order_return_request_order_id_id` (`order_id`, `id`),
  KEY `ix_order_return_request_status_created_at_id` (`status`, `created_at`, `id`),
  KEY `ix_order_return_request_order_id` (`order_id`),
  KEY `ix_order_return_request_requested_by` (`requested_by`),
  KEY `ix_order_return_request_reviewed_by` (`reviewed_by`),
  CONSTRAINT `ck_order_return_request_1` CHECK (version >= 0),
  CONSTRAINT `ck_order_return_request_2` CHECK (status NOT IN ('APPROVED','REJECTED','COMPLETED') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
  CONSTRAINT `ck_order_return_request_3` CHECK (status <> 'WITHDRAWN' OR withdrawn_at IS NOT NULL),
  CONSTRAINT `ck_order_return_request_4` CHECK (status <> 'COMPLETED' OR completed_at IS NOT NULL),
  CONSTRAINT `ck_order_return_request_5` CHECK (`status` IN ('PENDING','APPROVED','REJECTED','WITHDRAWN','COMPLETED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='取件后退回申请与审批';

-- P0/P1 | 异常与交接 | 独立异常工单与冻结依据
CREATE TABLE `exception_case` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `case_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '异常工单号',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `assignment_id` BIGINT NULL COMMENT '上报时的指派',
  `case_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '拒收、失联、物品不符、损坏或遗失等稳定代码',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OPEN' COMMENT '工单状态，独立于配送状态',
  `description` VARCHAR(2000) NOT NULL COMMENT '脱敏异常说明',
  `evidence_json` JSON NULL COMMENT '受控附件编号和交接证据，不含永久公开地址',
  `holds_fulfillment` TINYINT NOT NULL DEFAULT 0 COMMENT '该工单是否要求冻结普通履约',
  `reporter_user_id` BIGINT NOT NULL COMMENT '报告人',
  `handler_id` BIGINT NULL COMMENT '处理运营',
  `resolution` VARCHAR(2000) NULL COMMENT '解决方案与结论',
  `opened_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '登记时间',
  `resolved_at` DATETIME(3) NULL COMMENT '解决时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_exception_case_case_no` (`case_no`),
  KEY `ix_exception_case_order_id_status_id` (`order_id`, `status`, `id`),
  KEY `ix_exception_case_status_opened_at_id` (`status`, `opened_at`, `id`),
  KEY `ix_exception_case_handler_id_status_id` (`handler_id`, `status`, `id`),
  KEY `ix_exception_case_order_id_assignment_id` (`order_id`, `assignment_id`),
  KEY `ix_exception_case_reporter_user_id` (`reporter_user_id`),
  CONSTRAINT `ck_exception_case_1` CHECK (holds_fulfillment IN (0,1)),
  CONSTRAINT `ck_exception_case_2` CHECK (version >= 0),
  CONSTRAINT `ck_exception_case_3` CHECK ((status = 'RESOLVED' AND resolved_at IS NOT NULL AND resolution IS NOT NULL AND handler_id IS NOT NULL) OR (status <> 'RESOLVED' AND resolved_at IS NULL)),
  CONSTRAINT `ck_exception_case_4` CHECK (`status` IN ('OPEN','PROCESSING','RESOLVED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='独立异常工单与冻结依据';

-- P0 | 异常与交接 | 独立取件码、送达码、退回码与核验证据
CREATE TABLE `custody_record` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `assignment_id` BIGINT NOT NULL COMMENT '验证码绑定的实际指派',
  `assignment_epoch` BIGINT NOT NULL COMMENT '验证码绑定的执行代次',
  `action` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '取件、送达或退回交接',
  `issue_version` BIGINT NOT NULL COMMENT '本单同动作的签发版本',
  `code_hash` BINARY(32) NOT NULL COMMENT '绑定订单、动作、版本和随机量的验证码 HMAC，不存明文',
  `code_nonce` BINARY(16) NOT NULL COMMENT '摘要域隔离随机量',
  `hash_key_version` SMALLINT NOT NULL COMMENT 'HMAC 密钥版本',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ISSUED' COMMENT '验证码生命周期',
  `issued_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '签发时间',
  `code_expires_at` DATETIME(3) NOT NULL COMMENT '到达该时刻即过期',
  `failed_attempts` INT NOT NULL DEFAULT 0 COMMENT '本次签发连续核验失败次数',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '失败上限，达到即锁定',
  `consumed_at` DATETIME(3) NULL COMMENT '核验成功及物理交接确认时间',
  `actor_user_id` BIGINT NULL COMMENT '提交成功核验的骑手账户',
  `return_request_id` BIGINT NULL COMMENT '退回动作对应的审批请求',
  `evidence_json` JSON NULL COMMENT '交接凭证的受控引用',
  `active_action` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin GENERATED ALWAYS AS (CASE WHEN status IN ('ISSUED','LOCKED') THEN action ELSE NULL END) STORED COMMENT '每单每动作最多一份尚未结束的签发',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '核验、失败次数与重置竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_custody_record_order_id_action_issue_version` (`order_id`, `action`, `issue_version`),
  UNIQUE KEY `uk_custody_record_order_id_active_action` (`order_id`, `active_action`),
  KEY `ix_custody_record_status_code_expires_at_id` (`status`, `code_expires_at`, `id`),
  KEY `ix_custody_record_order_id_assignment_id_assignment_epoch` (`order_id`, `assignment_id`, `assignment_epoch`),
  KEY `ix_custody_record_actor_user_id` (`actor_user_id`),
  KEY `ix_custody_record_order_id_return_request_id` (`order_id`, `return_request_id`),
  CONSTRAINT `ck_custody_record_1` CHECK (assignment_epoch > 0 AND issue_version > 0 AND hash_key_version > 0),
  CONSTRAINT `ck_custody_record_2` CHECK (max_attempts > 0 AND failed_attempts >= 0 AND failed_attempts <= max_attempts),
  CONSTRAINT `ck_custody_record_3` CHECK (code_expires_at > issued_at),
  CONSTRAINT `ck_custody_record_4` CHECK (version >= 0),
  CONSTRAINT `ck_custody_record_5` CHECK (status <> 'ISSUED' OR failed_attempts < max_attempts),
  CONSTRAINT `ck_custody_record_6` CHECK ((status = 'CONSUMED' AND consumed_at IS NOT NULL AND actor_user_id IS NOT NULL) OR (status <> 'CONSUMED' AND consumed_at IS NULL)),
  CONSTRAINT `ck_custody_record_7` CHECK ((action = 'RETURN' AND return_request_id IS NOT NULL) OR (action <> 'RETURN' AND return_request_id IS NULL)),
  CONSTRAINT `ck_custody_record_8` CHECK (`action` IN ('PICKUP','DROPOFF','RETURN')),
  CONSTRAINT `ck_custody_record_9` CHECK (`status` IN ('ISSUED','LOCKED','CONSUMED','REVOKED','EXPIRED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='独立取件码、送达码、退回码与核验证据';

-- P0/P2 | 支付与退款 | 平台原运费与重量补款支付事实
CREATE TABLE `payment_order` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '所属配送单',
  `pay_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '平台支付请求号，重试不随意换号',
  `business_type` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DELIVERY_FEE' COMMENT '原运费或重量补款',
  `business_id` BIGINT NOT NULL COMMENT '原运费取订单 ID；补款取调整单 ID',
  `channel` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'MOCK' COMMENT '支付渠道适配标识',
  `channel_txn_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '成功渠道交易号；未知时必须为 NULL 而非空串',
  `amount_cent` BIGINT NOT NULL COMMENT '应收金额，分',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CREATED' COMMENT '晚到成功仍记为成功，再决定退款，不能抹去到账事实',
  `refunded_cent` BIGINT NOT NULL DEFAULT 0 COMMENT '已成功退款金额',
  `reserved_refund_cent` BIGINT NOT NULL DEFAULT 0 COMMENT '有效处理中退款预留',
  `expires_at` DATETIME(3) NOT NULL COMMENT '支付意图截止',
  `succeeded_at` DATETIME(3) NULL COMMENT '平台确认成功时间',
  `closed_at` DATETIME(3) NULL COMMENT '关闭时间；晚到成功可保留先前关闭时间',
  `next_query_at` DATETIME(3) NULL COMMENT '未知结果主动查单时间',
  `last_result` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'NONE' COMMENT '最近渠道结果；UNKNOWN 不能当失败',
  `active_business_type` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin GENERATED ALWAYS AS (CASE WHEN status IN ('CREATED','PROCESSING') THEN business_type ELSE NULL END) STORED COMMENT '同一业务最多一个未结束支付意图',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '资金更新版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_order_pay_no` (`pay_no`),
  UNIQUE KEY `uk_payment_order_channel_channel_txn_no` (`channel`, `channel_txn_no`),
  UNIQUE KEY `uk_payment_order_active_business_type_business_id` (`active_business_type`, `business_id`),
  UNIQUE KEY `uk_payment_order_order_id_id` (`order_id`, `id`),
  UNIQUE KEY `uk_payment_order_id_channel` (`id`, `channel`),
  KEY `ix_payment_order_order_id_business_type_created_at_id` (`order_id`, `business_type`, `created_at`, `id`),
  KEY `ix_payment_order_status_next_query_at_id` (`status`, `next_query_at`, `id`),
  KEY `ix_payment_order_status_expires_at_id` (`status`, `expires_at`, `id`),
  CONSTRAINT `ck_payment_order_1` CHECK (amount_cent > 0),
  CONSTRAINT `ck_payment_order_2` CHECK (refunded_cent >= 0 AND reserved_refund_cent >= 0 AND refunded_cent + reserved_refund_cent <= amount_cent),
  CONSTRAINT `ck_payment_order_3` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_payment_order_4` CHECK (channel_txn_no IS NULL OR channel_txn_no <> ''),
  CONSTRAINT `ck_payment_order_5` CHECK (business_type <> 'DELIVERY_FEE' OR business_id = order_id),
  CONSTRAINT `ck_payment_order_6` CHECK (status <> 'SUCCEEDED' OR (succeeded_at IS NOT NULL AND channel_txn_no IS NOT NULL)),
  CONSTRAINT `ck_payment_order_7` CHECK (version >= 0),
  CONSTRAINT `ck_payment_order_8` CHECK (expires_at > created_at),
  CONSTRAINT `ck_payment_order_9` CHECK (`business_type` IN ('DELIVERY_FEE','WEIGHT_ADJUSTMENT')),
  CONSTRAINT `ck_payment_order_10` CHECK (`status` IN ('CREATED','PROCESSING','SUCCEEDED','FAILED','CLOSED')),
  CONSTRAINT `ck_payment_order_11` CHECK (`last_result` IN ('NONE','SUCCESS','FAILURE','UNKNOWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='平台原运费与重量补款支付事实';

-- P0 | 支付与退款 | 退款申请、预留占用与结果
CREATE TABLE `refund_order` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `payment_id` BIGINT NOT NULL COMMENT '原支付事实',
  `refund_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定平台退款号，超时查单仍使用同一编号',
  `request_key` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '同一支付中的退款业务幂等键，如 LATE_PAYMENT',
  `channel` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '必须与原支付渠道一致',
  `channel_refund_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '成功渠道退款流水',
  `amount_cent` BIGINT NOT NULL COMMENT '本次退款金额，分',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CREATED' COMMENT '渠道结果未知时保持 PROCESSING',
  `reservation_state` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'RESERVED' COMMENT '预留、已计入成功退款或确定失败后释放',
  `reason` VARCHAR(500) NOT NULL COMMENT '退款原因',
  `requested_by` BIGINT NULL COMMENT '用户或运营；后台补偿可为空并记录审计身份',
  `succeeded_at` DATETIME(3) NULL COMMENT '确认渠道成功时间',
  `failed_at` DATETIME(3) NULL COMMENT '确定失败时间，超时不能直接填入',
  `next_query_at` DATETIME(3) NULL COMMENT '主动查询/重试时刻',
  `last_result` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'NONE' COMMENT '渠道结果',
  `last_error_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '脱敏渠道错误码',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '退款状态竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_refund_order_refund_no` (`refund_no`),
  UNIQUE KEY `uk_refund_order_payment_id_request_key` (`payment_id`, `request_key`),
  UNIQUE KEY `uk_refund_order_channel_channel_refund_no` (`channel`, `channel_refund_no`),
  UNIQUE KEY `uk_refund_order_payment_id_id` (`payment_id`, `id`),
  KEY `ix_refund_order_status_next_query_at_id` (`status`, `next_query_at`, `id`),
  KEY `ix_refund_order_payment_id_channel` (`payment_id`, `channel`),
  KEY `ix_refund_order_requested_by` (`requested_by`),
  CONSTRAINT `ck_refund_order_1` CHECK (amount_cent > 0),
  CONSTRAINT `ck_refund_order_2` CHECK (version >= 0),
  CONSTRAINT `ck_refund_order_3` CHECK (channel_refund_no IS NULL OR channel_refund_no <> ''),
  CONSTRAINT `ck_refund_order_4` CHECK ((status IN ('CREATED','PROCESSING') AND reservation_state = 'RESERVED') OR (status = 'SUCCEEDED' AND reservation_state = 'CONSUMED' AND succeeded_at IS NOT NULL AND channel_refund_no IS NOT NULL) OR (status = 'FAILED' AND reservation_state = 'RELEASED' AND failed_at IS NOT NULL)),
  CONSTRAINT `ck_refund_order_5` CHECK (`status` IN ('CREATED','PROCESSING','SUCCEEDED','FAILED')),
  CONSTRAINT `ck_refund_order_6` CHECK (`reservation_state` IN ('RESERVED','CONSUMED','RELEASED')),
  CONSTRAINT `ck_refund_order_7` CHECK (`last_result` IN ('NONE','SUCCESS','FAILURE','UNKNOWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='退款申请、预留占用与结果';

-- P0 | 支付与退款 | 验签后的渠道回调与重复投递证据
CREATE TABLE `payment_callback_inbox` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `channel` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '渠道',
  `callback_event_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '渠道事件号；无事件号时用规范化内容派生稳定编号',
  `callback_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '支付或退款',
  `payment_id` BIGINT NOT NULL COMMENT '已校验归属的支付事实',
  `refund_id` BIGINT NULL COMMENT '退款回调对应退款单',
  `channel_txn_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '对应渠道交易/退款号',
  `amount_cent` BIGINT NOT NULL COMMENT '回调声明金额，必须与业务记录比对',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `payload_hash` BINARY(32) NOT NULL COMMENT '规范化已验签回调摘要',
  `payload_cipher` MEDIUMBLOB NULL COMMENT '如需保留原文，使用加密封装而非明文 JSON',
  `crypto_key_version` SMALLINT NULL COMMENT '回调原文密钥版本',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'RECEIVED' COMMENT '可恢复处理状态',
  `received_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '首次接收时间',
  `processed_at` DATETIME(3) NULL COMMENT '已记账完成或已拒绝时间',
  `failure_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '拒绝或处理失败原因',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '重放/处理竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_callback_inbox_channel_callback_event_no` (`channel`, `callback_event_no`),
  KEY `ix_payment_callback_inbox_status_received_at_id` (`status`, `received_at`, `id`),
  KEY `ix_payment_callback_inbox_payment_id_channel` (`payment_id`, `channel`),
  KEY `ix_payment_callback_inbox_payment_id_refund_id` (`payment_id`, `refund_id`),
  CONSTRAINT `ck_payment_callback_inbox_1` CHECK (amount_cent > 0),
  CONSTRAINT `ck_payment_callback_inbox_2` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_payment_callback_inbox_3` CHECK (version >= 0),
  CONSTRAINT `ck_payment_callback_inbox_4` CHECK ((callback_type = 'PAYMENT' AND refund_id IS NULL) OR (callback_type = 'REFUND' AND refund_id IS NOT NULL)),
  CONSTRAINT `ck_payment_callback_inbox_5` CHECK (status = 'RECEIVED' OR processed_at IS NOT NULL),
  CONSTRAINT `ck_payment_callback_inbox_6` CHECK ((payload_cipher IS NULL AND crypto_key_version IS NULL) OR (payload_cipher IS NOT NULL AND crypto_key_version > 0)),
  CONSTRAINT `ck_payment_callback_inbox_7` CHECK (`callback_type` IN ('PAYMENT','REFUND')),
  CONSTRAINT `ck_payment_callback_inbox_8` CHECK (`status` IN ('RECEIVED','PROCESSED','REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='验签后的渠道回调与重复投递证据';

-- P0/P1 | 支付与退款 | 渠道调用、查单和未知结果记录
CREATE TABLE `payment_channel_attempt` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `payment_id` BIGINT NOT NULL COMMENT '原支付',
  `refund_id` BIGINT NULL COMMENT '涉及退款时关联退款单',
  `operation` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '支付、关闭、支付查询、退款或退款查询',
  `channel_request_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '实际发给渠道的稳定业务请求号，重试不更换',
  `attempt_no` INT NOT NULL COMMENT '该操作请求的第几次网络尝试',
  `result` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '成功、确定失败或结果未知',
  `request_hash` BINARY(32) NOT NULL COMMENT '脱敏请求摘要',
  `response_summary_json` JSON NULL COMMENT '脱敏响应摘要，禁止保存签名密钥',
  `error_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '错误码',
  `started_at` DATETIME(3) NOT NULL COMMENT '调用开始',
  `finished_at` DATETIME(3) NOT NULL COMMENT '返回或本地超时时间',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_channel_attempt_payment_id_operation_chann_9f390308ad` (`payment_id`, `operation`, `channel_request_no`, `attempt_no`),
  KEY `ix_payment_channel_attempt_payment_id_created_at_id` (`payment_id`, `created_at`, `id`),
  KEY `ix_payment_channel_attempt_payment_id_refund_id` (`payment_id`, `refund_id`),
  CONSTRAINT `ck_payment_channel_attempt_1` CHECK (attempt_no > 0),
  CONSTRAINT `ck_payment_channel_attempt_2` CHECK (finished_at >= started_at),
  CONSTRAINT `ck_payment_channel_attempt_3` CHECK ((operation IN ('REFUND','QUERY_REFUND') AND refund_id IS NOT NULL) OR (operation IN ('PAY','CLOSE_PAY','QUERY_PAY') AND refund_id IS NULL)),
  CONSTRAINT `ck_payment_channel_attempt_4` CHECK (`operation` IN ('PAY','CLOSE_PAY','QUERY_PAY','REFUND','QUERY_REFUND')),
  CONSTRAINT `ck_payment_channel_attempt_5` CHECK (`result` IN ('SUCCESS','FAILURE','UNKNOWN'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='渠道调用、查单和未知结果记录';

-- P0 | 位置 | 服务端采样的历史位置
CREATE TABLE `location_point` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `rider_id` BIGINT NOT NULL COMMENT '骑手，不能采用请求中任意 riderId',
  `session_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '服务端已授权的位置会话',
  `seq` BIGINT NOT NULL COMMENT '同会话单调序号，Redis 维护热位置高水位',
  `longitude` DECIMAL(10,7) NOT NULL COMMENT '经度',
  `latitude` DECIMAL(10,7) NOT NULL COMMENT '纬度',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '原始坐标系',
  `accuracy_m` DECIMAL(10,2) NULL COMMENT '设备报告精度，仅作辅助',
  `captured_at` DATETIME(3) NOT NULL COMMENT '设备采集时间，不能单独用于新鲜度',
  `received_at` DATETIME(3) NOT NULL COMMENT '服务端接收时间，轨迹过滤依据',
  `source` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '模拟或设备定位',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_location_point_rider_id_session_id_seq` (`rider_id`, `session_id`, `seq`),
  KEY `ix_location_point_rider_id_received_at_id` (`rider_id`, `received_at`, `id`),
  KEY `ix_location_point_received_at_id` (`received_at`, `id`),
  CONSTRAINT `ck_location_point_1` CHECK (seq > 0),
  CONSTRAINT `ck_location_point_2` CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_location_point_3` CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_location_point_4` CHECK (accuracy_m IS NULL OR accuracy_m >= 0),
  CONSTRAINT `ck_location_point_5` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09')),
  CONSTRAINT `ck_location_point_6` CHECK (`source` IN ('DEVICE','MOCK'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='服务端采样的历史位置';

-- P1 | 账户与骑手 | 无注册收件人的限时授权
CREATE TABLE `receiver_access` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '唯一授权的配送单',
  `token_hash` BINARY(32) NOT NULL COMMENT '高熵授权 token 的摘要，永不保存明文',
  `scope` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PROGRESS' COMMENT '只允许查询的范围，不授予取消、退款或骑手操作',
  `issued_by` BIGINT NOT NULL COMMENT '订单所有者或授权运营',
  `issued_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '签发时间',
  `expires_at` DATETIME(3) NOT NULL COMMENT '有效期',
  `revoked_at` DATETIME(3) NULL COMMENT '撤销时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '撤销竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_receiver_access_token_hash` (`token_hash`),
  KEY `ix_receiver_access_order_id_expires_at_id` (`order_id`, `expires_at`, `id`),
  KEY `ix_receiver_access_expires_at_id` (`expires_at`, `id`),
  KEY `ix_receiver_access_issued_by` (`issued_by`),
  CONSTRAINT `ck_receiver_access_1` CHECK (expires_at > issued_at),
  CONSTRAINT `ck_receiver_access_2` CHECK (revoked_at IS NULL OR revoked_at >= issued_at),
  CONSTRAINT `ck_receiver_access_3` CHECK (version >= 0),
  CONSTRAINT `ck_receiver_access_4` CHECK (`scope` IN ('PROGRESS','PROGRESS_AND_LOCATION'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='无注册收件人的限时授权';

-- P1 | 报价与订单 | 完成订单的一次评价
CREATE TABLE `order_evaluation` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `order_id` BIGINT NOT NULL COMMENT '每单最多一次评价',
  `user_id` BIGINT NOT NULL COMMENT '必须是下单用户',
  `assignment_id` BIGINT NOT NULL COMMENT '实际完成配送的历史指派',
  `rider_id` BIGINT NOT NULL COMMENT '被评价的实际骑手',
  `rating` TINYINT NOT NULL COMMENT '1 到 5 分',
  `comment` VARCHAR(1000) NULL COMMENT '评价内容，接口需过滤敏感信息',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_evaluation_order_id` (`order_id`),
  KEY `ix_order_evaluation_rider_id_created_at_id` (`rider_id`, `created_at`, `id`),
  KEY `ix_order_evaluation_order_id_user_id` (`order_id`, `user_id`),
  KEY `ix_order_evaluation_order_id_assignment_id_rider_id` (`order_id`, `assignment_id`, `rider_id`),
  CONSTRAINT `ck_order_evaluation_1` CHECK (rating BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='完成订单的一次评价';

-- P0 | 可靠性与审计 | 命令请求的持久幂等结果
CREATE TABLE `api_idempotency` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `actor_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '命名空间区分用户、外部系统、系统任务',
  `actor_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '该命名空间内的操作者编号',
  `action` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定命令名，不能把所有接口合为一个作用域',
  `request_key` VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '大小写敏感的 Idempotency-Key',
  `request_hash` BINARY(32) NOT NULL COMMENT '规范化请求摘要；相同键不同内容必须冲突',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '同步命令随业务同事务提交成功/确定失败结果',
  `http_status` SMALLINT NOT NULL COMMENT '可重放 HTTP 结果码',
  `result_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '结果资源类型',
  `result_ref` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '结果主键或公开业务编号',
  `result_json` JSON NULL COMMENT '最小可重放结果，不复制联系人等敏感快照',
  `completed_at` DATETIME(3) NOT NULL COMMENT '已提交结果时间',
  `expires_at` DATETIME(3) NOT NULL COMMENT '至少保留 24 小时；永久业务唯一键另行保留',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_api_idempotency_actor_type_actor_id_action_request_key` (`actor_type`, `actor_id`, `action`, `request_key`),
  KEY `ix_api_idempotency_expires_at_id` (`expires_at`, `id`),
  CONSTRAINT `ck_api_idempotency_1` CHECK (http_status BETWEEN 200 AND 599),
  CONSTRAINT `ck_api_idempotency_2` CHECK (expires_at > completed_at),
  CONSTRAINT `ck_api_idempotency_3` CHECK (`actor_type` IN ('USER','EXTERNAL','SYSTEM')),
  CONSTRAINT `ck_api_idempotency_4` CHECK (`status` IN ('SUCCEEDED','FAILED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='命令请求的持久幂等结果';

-- P0/P1 | 可靠性与审计 | 与业务事务共同提交的待发送事件
CREATE TABLE `outbox_event` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '全局稳定事件号，重发不更换',
  `aggregate_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '聚合类型',
  `aggregate_id` BIGINT NOT NULL COMMENT '聚合主键；多态引用，由业务校验',
  `aggregate_version` BIGINT NOT NULL COMMENT '聚合变更版本',
  `event_type` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '事件类型',
  `schema_version` INT NOT NULL DEFAULT 1 COMMENT '事件载荷契约版本',
  `payload_json` JSON NOT NULL COMMENT '完整事件信封，不包含密钥/验证码/联系人明文',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'READY' COMMENT '待发送、领取发送中、已确认或最终失败',
  `attempts` INT NOT NULL DEFAULT 0 COMMENT '实际发送尝试数',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '尝试上限',
  `next_attempt_at` DATETIME(3) NOT NULL COMMENT '下次发送时间',
  `claim_owner` VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '当前后台处理实例',
  `claim_token` VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '本次领取令牌，旧领取者不得更新新结果',
  `lease_until` DATETIME(3) NULL COMMENT '后台处理租约，与骑手持货权无关',
  `sent_at` DATETIME(3) NULL COMMENT '确认成功后记录，不表示业务已消费',
  `last_error` VARCHAR(1000) NULL COMMENT '脱敏发送错误',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `occurred_at` DATETIME(3) NOT NULL COMMENT '业务事件时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '领取与恢复版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_outbox_event_event_id` (`event_id`),
  UNIQUE KEY `uk_outbox_event_aggregate_type_aggregate_id_aggregate_b70e87f8ba` (`aggregate_type`, `aggregate_id`, `aggregate_version`, `event_type`),
  KEY `ix_outbox_event_status_next_attempt_at_id` (`status`, `next_attempt_at`, `id`),
  KEY `ix_outbox_event_status_lease_until_id` (`status`, `lease_until`, `id`),
  CONSTRAINT `ck_outbox_event_1` CHECK (aggregate_version >= 0 AND schema_version > 0),
  CONSTRAINT `ck_outbox_event_2` CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts),
  CONSTRAINT `ck_outbox_event_3` CHECK (version >= 0),
  CONSTRAINT `ck_outbox_event_4` CHECK ((status = 'SENDING' AND claim_owner IS NOT NULL AND claim_token IS NOT NULL AND lease_until IS NOT NULL) OR (status <> 'SENDING' AND claim_owner IS NULL AND claim_token IS NULL AND lease_until IS NULL)),
  CONSTRAINT `ck_outbox_event_5` CHECK (status <> 'SENT' OR sent_at IS NOT NULL),
  CONSTRAINT `ck_outbox_event_6` CHECK (`status` IN ('READY','SENDING','SENT','DEAD'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='与业务事务共同提交的待发送事件';

-- P1 | 可靠性与审计 | 消费成功去重凭据
CREATE TABLE `consumed_event` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `consumer_name` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定消费逻辑名称，实例 ID 不能作为消费名',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定事件号；不对本地 Outbox 建物理外键',
  `payload_hash` BINARY(32) NOT NULL COMMENT '防同号不同内容事件',
  `processed_at` DATETIME(3) NOT NULL COMMENT '与业务事务一起提交的成功时间',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_consumed_event_consumer_name_event_id` (`consumer_name`, `event_id`),
  KEY `ix_consumed_event_processed_at_id` (`processed_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='消费成功去重凭据';

-- P0/P1 | 可靠性与审计 | 可领取、可恢复的持久到期任务
CREATE TABLE `scheduled_job` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `job_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '支付关闭、邀约超时、预约触发等稳定类型',
  `business_type` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '目标命名空间，多消费组重试需区分消费名',
  `biz_id` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '业务编号，可容纳订单 ID 或事件号',
  `generation` BIGINT NOT NULL DEFAULT 0 COMMENT '预期轮次/代次，不能由旧任务覆盖新任务',
  `payload_json` JSON NOT NULL COMMENT '目标版本、轮次等最小命令输入',
  `due_at` DATETIME(3) NOT NULL COMMENT '到期或退避后可执行时间',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'READY' COMMENT '任务生命周期',
  `attempts` INT NOT NULL DEFAULT 0 COMMENT '执行尝试数',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '重试上限',
  `claim_owner` VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '当前后台处理实例',
  `claim_token` VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '本次领取令牌，旧领取者不得更新新结果',
  `lease_until` DATETIME(3) NULL COMMENT '后台处理租约，与骑手持货权无关',
  `finished_at` DATETIME(3) NULL COMMENT '成功、取消或最终失败时间',
  `last_error` VARCHAR(1000) NULL COMMENT '脱敏失败原因',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '领取和条件更新版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_scheduled_job_job_type_business_type_biz_id_generation` (`job_type`, `business_type`, `biz_id`, `generation`),
  KEY `ix_scheduled_job_status_due_at_id` (`status`, `due_at`, `id`),
  KEY `ix_scheduled_job_status_lease_until_id` (`status`, `lease_until`, `id`),
  CONSTRAINT `ck_scheduled_job_1` CHECK (generation >= 0 AND version >= 0),
  CONSTRAINT `ck_scheduled_job_2` CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts),
  CONSTRAINT `ck_scheduled_job_3` CHECK ((status = 'RUNNING' AND claim_owner IS NOT NULL AND claim_token IS NOT NULL AND lease_until IS NOT NULL) OR (status <> 'RUNNING' AND claim_owner IS NULL AND claim_token IS NULL AND lease_until IS NULL)),
  CONSTRAINT `ck_scheduled_job_4` CHECK (status NOT IN ('SUCCEEDED','CANCELLED','DEAD') OR finished_at IS NOT NULL),
  CONSTRAINT `ck_scheduled_job_5` CHECK (`status` IN ('READY','RUNNING','RETRY','SUCCEEDED','CANCELLED','DEAD'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='可领取、可恢复的持久到期任务';

-- P1 | 可靠性与审计 | 消费退避、停放及受控重放
CREATE TABLE `message_failure` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `consumer_name` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '逻辑消费者',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '原事件号，重放不能伪造新事件绕过去重',
  `event_type` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '事件类型',
  `payload_json` JSON NOT NULL COMMENT '可重试的原始事件信封，须满足脱敏约定',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'RETRY_WAIT' COMMENT '重试等待、处理、死信停放或已恢复',
  `attempts` INT NOT NULL DEFAULT 0 COMMENT '消费重试次数',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '重试上限',
  `next_attempt_at` DATETIME(3) NULL COMMENT '重试时间，停放后可为空',
  `claim_owner` VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '当前后台处理实例',
  `claim_token` VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '本次领取令牌，旧领取者不得更新新结果',
  `lease_until` DATETIME(3) NULL COMMENT '后台处理租约，与骑手持货权无关',
  `last_error` VARCHAR(1000) NOT NULL COMMENT '脱敏错误',
  `resolved_at` DATETIME(3) NULL COMMENT '恢复成功或人工终结时间',
  `resolution` VARCHAR(1000) NULL COMMENT '恢复/人工处理说明',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '重放竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_message_failure_consumer_name_event_id` (`consumer_name`, `event_id`),
  KEY `ix_message_failure_status_next_attempt_at_id` (`status`, `next_attempt_at`, `id`),
  KEY `ix_message_failure_status_lease_until_id` (`status`, `lease_until`, `id`),
  CONSTRAINT `ck_message_failure_1` CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts),
  CONSTRAINT `ck_message_failure_2` CHECK (version >= 0),
  CONSTRAINT `ck_message_failure_3` CHECK ((status = 'CLAIMED' AND claim_owner IS NOT NULL AND claim_token IS NOT NULL AND lease_until IS NOT NULL) OR (status <> 'CLAIMED' AND claim_owner IS NULL AND claim_token IS NULL AND lease_until IS NULL)),
  CONSTRAINT `ck_message_failure_4` CHECK (status NOT IN ('RETRY_WAIT','CLAIMED') OR next_attempt_at IS NOT NULL),
  CONSTRAINT `ck_message_failure_5` CHECK (status <> 'RESOLVED' OR (resolved_at IS NOT NULL AND resolution IS NOT NULL)),
  CONSTRAINT `ck_message_failure_6` CHECK (`status` IN ('RETRY_WAIT','CLAIMED','PARKED','RESOLVED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='消费退避、停放及受控重放';

-- P0/P1 | 可靠性与审计 | 关键操作的追加审计
CREATE TABLE `operation_audit` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `actor_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '操作者身份类别',
  `actor_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '该命名空间内的主体编号',
  `action` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '冻结、解冻、改派、退款、规则发布等操作',
  `target_type` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '资源类型',
  `target_id` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '资源编号，多态引用',
  `reason` VARCHAR(1000) NOT NULL COMMENT '操作原因',
  `before_json` JSON NULL COMMENT '必要的脱敏前值，不复制密钥和联系人',
  `after_json` JSON NULL COMMENT '必要的脱敏后值',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `occurred_at` DATETIME(3) NOT NULL COMMENT '操作时间',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  KEY `ix_operation_audit_target_type_target_id_occurred_at_id` (`target_type`, `target_id`, `occurred_at`, `id`),
  KEY `ix_operation_audit_actor_type_actor_id_occurred_at_id` (`actor_type`, `actor_id`, `occurred_at`, `id`),
  KEY `ix_operation_audit_occurred_at_id` (`occurred_at`, `id`),
  CONSTRAINT `ck_operation_audit_1` CHECK (`actor_type` IN ('USER','RIDER','OPS','SYSTEM','EXTERNAL'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='关键操作的追加审计';

-- P1 | 通知 | 可查询的站内通知
CREATE TABLE `inbox_notification` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `user_id` BIGINT NOT NULL COMMENT '接收账户，下单用户或骑手',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '业务事件，不绑定本地 Outbox 的保留时间',
  `template_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '通知模板',
  `order_id` BIGINT NULL COMMENT '涉及订单时关联',
  `title` VARCHAR(200) NOT NULL COMMENT '通知标题',
  `content_json` JSON NOT NULL COMMENT '最小展示参数，不放完整联系人',
  `read_at` DATETIME(3) NULL COMMENT '读取时间',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_inbox_notification_user_id_event_id_template_code` (`user_id`, `event_id`, `template_code`),
  KEY `ix_inbox_notification_user_id_read_at_created_at_id` (`user_id`, `read_at`, `created_at`, `id`),
  KEY `ix_inbox_notification_order_id` (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='可查询的站内通知';

-- P1 | 通知 | 外部通知幂等投递和未知结果
CREATE TABLE `notification_delivery` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '来源事件号',
  `inbox_notification_id` BIGINT NULL COMMENT '已注册账户的站内通知；无注册收件人可为空',
  `channel` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '短信、邮件或开发模拟',
  `template_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '模板代码',
  `recipient_hash` BINARY(32) NOT NULL COMMENT '收件地址/号码的 HMAC，参与去重',
  `recipient_cipher` VARBINARY(1024) NOT NULL COMMENT '渠道目标密文',
  `crypto_key_version` SMALLINT NOT NULL COMMENT '密钥版本',
  `provider` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '渠道适配器',
  `provider_request_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '稳定渠道请求号',
  `provider_message_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '渠道回执号',
  `secret_payload_cipher` VARBINARY(4096) NULL COMMENT '需要可靠投递的验证码等敏感模板参数加密封装；成功或过期后受控清理',
  `payload_expires_at` DATETIME(3) NULL COMMENT '敏感模板参数可投递期限；过期后禁止继续发送旧验证码',
  `payload_json` JSON NOT NULL COMMENT '不含验证码或联系人明文的模板参数',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PENDING' COMMENT '结果未知先查单/人工核对，不能盲目重发',
  `attempts` INT NOT NULL DEFAULT 0 COMMENT '调用尝试',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '重试上限',
  `next_attempt_at` DATETIME(3) NULL COMMENT '下次发送或查询',
  `claim_owner` VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '当前后台处理实例',
  `claim_token` VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '本次领取令牌，旧领取者不得更新新结果',
  `lease_until` DATETIME(3) NULL COMMENT '后台处理租约，与骑手持货权无关',
  `succeeded_at` DATETIME(3) NULL COMMENT '渠道确认成功',
  `last_error` VARCHAR(1000) NULL COMMENT '脱敏错误',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '竞争版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_notification_delivery_event_id_channel_recipient_h_fcf5d6a792` (`event_id`, `channel`, `recipient_hash`, `template_code`),
  UNIQUE KEY `uk_notification_delivery_provider_provider_request_no` (`provider`, `provider_request_no`),
  KEY `ix_notification_delivery_status_next_attempt_at_id` (`status`, `next_attempt_at`, `id`),
  KEY `ix_notification_delivery_status_lease_until_id` (`status`, `lease_until`, `id`),
  KEY `ix_notification_delivery_inbox_notification_id` (`inbox_notification_id`),
  CONSTRAINT `ck_notification_delivery_1` CHECK (crypto_key_version > 0),
  CONSTRAINT `ck_notification_delivery_2` CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts),
  CONSTRAINT `ck_notification_delivery_3` CHECK (version >= 0),
  CONSTRAINT `ck_notification_delivery_4` CHECK ((status = 'SENDING' AND claim_owner IS NOT NULL AND claim_token IS NOT NULL AND lease_until IS NOT NULL) OR (status <> 'SENDING' AND claim_owner IS NULL AND claim_token IS NULL AND lease_until IS NULL)),
  CONSTRAINT `ck_notification_delivery_5` CHECK (status <> 'SUCCEEDED' OR succeeded_at IS NOT NULL),
  CONSTRAINT `ck_notification_delivery_6` CHECK (`channel` IN ('SMS','EMAIL','MOCK')),
  CONSTRAINT `ck_notification_delivery_7` CHECK (`status` IN ('PENDING','SENDING','UNKNOWN','SUCCEEDED','FAILED')),
  CONSTRAINT `ck_notification_delivery_8` CHECK (secret_payload_cipher IS NULL OR payload_expires_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='外部通知幂等投递和未知结果';

-- P2 | 预约与调度扩展 | P2 取件前重量复核与独立补款
CREATE TABLE `order_weight_adjustment` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `adjustment_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '补差价单号',
  `order_id` BIGINT NOT NULL COMMENT '首个版本每单最多一笔重量调整',
  `assignment_id` BIGINT NOT NULL COMMENT '提出复核时的当前骑手指派',
  `declared_weight_g` INT NOT NULL COMMENT '原重量快照',
  `measured_weight_g` INT NOT NULL COMMENT '核实实际重量',
  `original_fee_cent` BIGINT NOT NULL COMMENT '原运费快照',
  `recalculated_fee_cent` BIGINT NOT NULL COMMENT '按原始规则重新计算的费用',
  `extra_fee_cent` BIGINT NOT NULL COMMENT '应补金额，不覆盖原配送报价',
  `pricing_snapshot_json` JSON NOT NULL COMMENT '原规则与差价计算证据',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'WAIT_CONFIRM' COMMENT '待确认、待支付、已补款或终结',
  `expires_at` DATETIME(3) NOT NULL COMMENT '确认/支付截止',
  `confirmed_at` DATETIME(3) NULL COMMENT '下单人确认时间',
  `paid_payment_id` BIGINT NULL COMMENT '补款成功支付事实',
  `paid_at` DATETIME(3) NULL COMMENT '补款成功时间',
  `closed_at` DATETIME(3) NULL COMMENT '拒绝、撤销或过期时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_order_weight_adjustment_adjustment_no` (`adjustment_no`),
  UNIQUE KEY `uk_order_weight_adjustment_order_id` (`order_id`),
  KEY `ix_order_weight_adjustment_status_expires_at_id` (`status`, `expires_at`, `id`),
  KEY `ix_order_weight_adjustment_order_id_assignment_id` (`order_id`, `assignment_id`),
  KEY `ix_order_weight_adjustment_order_id_paid_payment_id` (`order_id`, `paid_payment_id`),
  CONSTRAINT `ck_order_weight_adjustment_1` CHECK (declared_weight_g > 0 AND measured_weight_g > declared_weight_g),
  CONSTRAINT `ck_order_weight_adjustment_2` CHECK (original_fee_cent > 0 AND extra_fee_cent > 0 AND recalculated_fee_cent = original_fee_cent + extra_fee_cent),
  CONSTRAINT `ck_order_weight_adjustment_3` CHECK (expires_at > created_at),
  CONSTRAINT `ck_order_weight_adjustment_4` CHECK (version >= 0),
  CONSTRAINT `ck_order_weight_adjustment_5` CHECK (status NOT IN ('WAIT_PAYMENT','PAID') OR confirmed_at IS NOT NULL),
  CONSTRAINT `ck_order_weight_adjustment_6` CHECK (status <> 'PAID' OR (paid_payment_id IS NOT NULL AND paid_at IS NOT NULL)),
  CONSTRAINT `ck_order_weight_adjustment_7` CHECK (status NOT IN ('REJECTED','CANCELLED','EXPIRED') OR closed_at IS NOT NULL),
  CONSTRAINT `ck_order_weight_adjustment_8` CHECK (`status` IN ('WAIT_CONFIRM','WAIT_PAYMENT','PAID','REJECTED','CANCELLED','EXPIRED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P2 取件前重量复核与独立补款';

-- P2 | 预约与调度扩展 | P2 骑手当前路线入口
CREATE TABLE `rider_route` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `rider_id` BIGINT NOT NULL COMMENT '路线所属骑手',
  `city_code` VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '城市',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'ACTIVE' COMMENT '是否在执行',
  `route_version` BIGINT NOT NULL DEFAULT 0 COMMENT '当前提交的路线版本',
  `current_plan_id` BIGINT NULL COMMENT '当前已提交的不可变计划快照',
  `active_rider_id` BIGINT GENERATED ALWAYS AS (CASE WHEN status = 'ACTIVE' THEN rider_id ELSE NULL END) STORED COMMENT '每名骑手最多一条有效路线',
  `closed_at` DATETIME(3) NULL COMMENT '路线结束',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '入口行并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_rider_route_active_rider_id` (`active_rider_id`),
  KEY `ix_rider_route_rider_id` (`rider_id`),
  KEY `ix_rider_route_city_code` (`city_code`),
  KEY `ix_rider_route_id_current_plan_id_route_version` (`id`, `current_plan_id`, `route_version`),
  CONSTRAINT `ck_rider_route_1` CHECK (route_version >= 0 AND version >= 0),
  CONSTRAINT `ck_rider_route_2` CHECK ((current_plan_id IS NULL AND route_version = 0) OR (current_plan_id IS NOT NULL AND route_version > 0)),
  CONSTRAINT `ck_rider_route_3` CHECK ((status = 'ACTIVE' AND closed_at IS NULL) OR (status = 'CLOSED' AND closed_at IS NOT NULL)),
  CONSTRAINT `ck_rider_route_4` CHECK (`status` IN ('ACTIVE','CLOSED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P2 骑手当前路线入口';

-- P2 | 预约与调度扩展 | P2 不可变版本路线计划
CREATE TABLE `rider_route_plan` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `route_id` BIGINT NOT NULL COMMENT '路线入口',
  `route_version` BIGINT NOT NULL COMMENT '路线版本',
  `algorithm_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '插入策略版本',
  `based_on_version` BIGINT NOT NULL COMMENT '事务外计算所依据的版本',
  `total_distance_m` INT NOT NULL COMMENT '预计总道路距离',
  `total_duration_seconds` INT NOT NULL COMMENT '预计行程时长',
  `max_load_g` INT NOT NULL COMMENT '本计划车辆载重限制',
  `frozen_stop_count` INT NOT NULL DEFAULT 0 COMMENT '不得被新插入改动的前缀节点数',
  `constraint_snapshot_json` JSON NOT NULL COMMENT '承诺时限、最大绕行、路线来源等校验证据',
  `committed_at` DATETIME(3) NOT NULL COMMENT '版本提交时间',
  `trace_id` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '链路标识',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_rider_route_plan_route_id_route_version` (`route_id`, `route_version`),
  UNIQUE KEY `uk_rider_route_plan_route_id_id_route_version` (`route_id`, `id`, `route_version`),
  CONSTRAINT `ck_rider_route_plan_1` CHECK (route_version > 0 AND based_on_version >= 0 AND based_on_version < route_version),
  CONSTRAINT `ck_rider_route_plan_2` CHECK (total_distance_m >= 0 AND total_duration_seconds >= 0),
  CONSTRAINT `ck_rider_route_plan_3` CHECK (max_load_g > 0 AND frozen_stop_count >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P2 不可变版本路线计划';

-- P2 | 预约与调度扩展 | P2 路线版本中的取送节点
CREATE TABLE `route_stop` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `route_plan_id` BIGINT NOT NULL COMMENT '不可变路线版本',
  `stop_sequence` INT NOT NULL COMMENT '该版本中的节点顺序',
  `order_id` BIGINT NOT NULL COMMENT '服务订单',
  `assignment_id` BIGINT NOT NULL COMMENT '订单的实际承接',
  `stop_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '取件、送达或退回',
  `longitude` DECIMAL(10,7) NOT NULL COMMENT '节点经度快照',
  `latitude` DECIMAL(10,7) NOT NULL COMMENT '节点纬度快照',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '坐标系',
  `window_start_at` DATETIME(3) NULL COMMENT '节点服务时限起点',
  `window_end_at` DATETIME(3) NULL COMMENT '节点服务时限终点',
  `planned_arrival_at` DATETIME(3) NOT NULL COMMENT '预计到达',
  `load_after_g` INT NOT NULL COMMENT '完成该节点后的预计载重',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_route_stop_route_plan_id_stop_sequence` (`route_plan_id`, `stop_sequence`),
  UNIQUE KEY `uk_route_stop_route_plan_id_order_id_stop_type` (`route_plan_id`, `order_id`, `stop_type`),
  KEY `ix_route_stop_order_id_route_plan_id_id` (`order_id`, `route_plan_id`, `id`),
  KEY `ix_route_stop_order_id_assignment_id` (`order_id`, `assignment_id`),
  CONSTRAINT `ck_route_stop_1` CHECK (stop_sequence > 0 AND load_after_g >= 0),
  CONSTRAINT `ck_route_stop_2` CHECK (longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_route_stop_3` CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_route_stop_4` CHECK (window_start_at IS NULL OR window_end_at IS NULL OR window_end_at >= window_start_at),
  CONSTRAINT `ck_route_stop_5` CHECK (`stop_type` IN ('PICKUP','DROPOFF','RETURN')),
  CONSTRAINT `ck_route_stop_6` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P2 路线版本中的取送节点';

-- P2 | 预约与调度扩展 | P2 持货骑手更换与双方交接
CREATE TABLE `custody_handover` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `handover_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '交接单号',
  `order_id` BIGINT NOT NULL COMMENT '配送单',
  `from_rider_id` BIGINT NOT NULL COMMENT '原持货骑手，与旧指派强关联',
  `from_assignment_id` BIGINT NOT NULL COMMENT '原持货指派',
  `expected_epoch` BIGINT NOT NULL COMMENT '交接申请时的执行代次',
  `to_rider_id` BIGINT NOT NULL COMMENT '拟接货骑手',
  `to_assignment_id` BIGINT NULL COMMENT '最终确认事务创建的新指派',
  `status` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'REQUESTED' COMMENT '交接确认状态，不能作为普通抢单',
  `reason` VARCHAR(1000) NOT NULL COMMENT '更换持货人原因',
  `from_confirmed_at` DATETIME(3) NULL COMMENT '原骑手交出确认',
  `to_confirmed_at` DATETIME(3) NULL COMMENT '新骑手接收确认',
  `operator_id` BIGINT NULL COMMENT '最终确认运营',
  `confirmed_at` DATETIME(3) NULL COMMENT '双方容量和执行权变更提交时间',
  `longitude` DECIMAL(10,7) NULL COMMENT '确认交接地点',
  `latitude` DECIMAL(10,7) NULL COMMENT '确认交接地点',
  `coordinate_system` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '坐标系',
  `evidence_json` JSON NULL COMMENT '双方受控凭证引用',
  `deadline_at` DATETIME(3) NOT NULL COMMENT '确认期限，超时不能自动丢弃原持货责任',
  `open_order_id` BIGINT GENERATED ALWAYS AS (CASE WHEN status IN ('REQUESTED','FROM_CONFIRMED','BOTH_CONFIRMED') THEN order_id ELSE NULL END) STORED COMMENT '同单最多一个未结束交接',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_custody_handover_handover_no` (`handover_no`),
  UNIQUE KEY `uk_custody_handover_open_order_id` (`open_order_id`),
  KEY `ix_custody_handover_status_deadline_at_id` (`status`, `deadline_at`, `id`),
  KEY `ix_custody_handover_order_id_from_assignment_id_from__32b815f893` (`order_id`, `from_assignment_id`, `from_rider_id`, `expected_epoch`),
  KEY `ix_custody_handover_to_rider_id` (`to_rider_id`),
  KEY `ix_custody_handover_order_id_to_assignment_id_to_rider_id` (`order_id`, `to_assignment_id`, `to_rider_id`),
  KEY `ix_custody_handover_operator_id` (`operator_id`),
  CONSTRAINT `ck_custody_handover_1` CHECK (expected_epoch > 0 AND version >= 0),
  CONSTRAINT `ck_custody_handover_2` CHECK (deadline_at > created_at),
  CONSTRAINT `ck_custody_handover_3` CHECK (status NOT IN ('FROM_CONFIRMED','BOTH_CONFIRMED','COMPLETED') OR from_confirmed_at IS NOT NULL),
  CONSTRAINT `ck_custody_handover_4` CHECK (status NOT IN ('BOTH_CONFIRMED','COMPLETED') OR to_confirmed_at IS NOT NULL),
  CONSTRAINT `ck_custody_handover_5` CHECK (status <> 'COMPLETED' OR (to_assignment_id IS NOT NULL AND confirmed_at IS NOT NULL AND operator_id IS NOT NULL AND longitude IS NOT NULL AND latitude IS NOT NULL AND coordinate_system IS NOT NULL AND evidence_json IS NOT NULL)),
  CONSTRAINT `ck_custody_handover_6` CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  CONSTRAINT `ck_custody_handover_7` CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  CONSTRAINT `ck_custody_handover_8` CHECK ((longitude IS NULL AND latitude IS NULL AND coordinate_system IS NULL) OR (longitude IS NOT NULL AND latitude IS NOT NULL AND coordinate_system IS NOT NULL)),
  CONSTRAINT `ck_custody_handover_9` CHECK (`status` IN ('REQUESTED','FROM_CONFIRMED','BOTH_CONFIRMED','COMPLETED','CANCELLED','REJECTED')),
  CONSTRAINT `ck_custody_handover_10` CHECK (`coordinate_system` IN ('GCJ02','WGS84','BD09')),
  CONSTRAINT `ck_custody_handover_11` CHECK (from_rider_id <> to_rider_id),
  CONSTRAINT `ck_custody_handover_12` CHECK (to_assignment_id IS NULL OR to_assignment_id <> from_assignment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P2 持货骑手更换与双方交接';

-- P3 | 外部协同 | P3 外部建单幂等与运费责任
CREATE TABLE `external_order_request` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `client_id` BIGINT NOT NULL COMMENT '已认证外部调用方',
  `request_key` VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '来源的请求幂等键',
  `source_order_no` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '来源订单号',
  `request_hash` BINARY(32) NOT NULL COMMENT '标准化请求摘要，同来源单号不同内容应冲突',
  `order_id` BIGINT NULL COMMENT '成功时生成的配送单',
  `fee_payer` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '用户支付或获授权来源承担',
  `source_fee_reference` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '来源承担的授权核对参考号',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '与建单同事务保存的最终结果',
  `error_code` VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '拒绝原因',
  `processed_at` DATETIME(3) NOT NULL COMMENT '处理时间',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_external_order_request_client_id_request_key` (`client_id`, `request_key`),
  UNIQUE KEY `uk_external_order_request_client_id_source_order_no` (`client_id`, `source_order_no`),
  UNIQUE KEY `uk_external_order_request_order_id` (`order_id`),
  KEY `ix_external_order_request_client_id_order_id_source_order_no` (`client_id`, `order_id`, `source_order_no`),
  CONSTRAINT `ck_external_order_request_1` CHECK ((status = 'CREATED' AND order_id IS NOT NULL AND error_code IS NULL) OR (status = 'REJECTED' AND order_id IS NULL AND error_code IS NOT NULL)),
  CONSTRAINT `ck_external_order_request_2` CHECK (fee_payer <> 'PAID_BY_SOURCE' OR source_fee_reference IS NOT NULL),
  CONSTRAINT `ck_external_order_request_3` CHECK (`fee_payer` IN ('PAY_BY_USER','PAID_BY_SOURCE')),
  CONSTRAINT `ck_external_order_request_4` CHECK (`status` IN ('CREATED','REJECTED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P3 外部建单幂等与运费责任';

-- P3 | 外部协同 | P3 版本化履约回调重试
CREATE TABLE `external_callback_delivery` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `client_id` BIGINT NOT NULL COMMENT '外部接收方',
  `order_id` BIGINT NOT NULL COMMENT '该来源拥有的配送单',
  `event_id` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '回调事件幂等号',
  `order_version` BIGINT NOT NULL COMMENT '配送聚合版本，接收方应拒绝旧快照覆盖',
  `event_type` VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '回调类型',
  `callback_url_snapshot` VARCHAR(1000) NOT NULL COMMENT '审核过的回调地址快照',
  `payload_json` JSON NOT NULL COMMENT '配送单号、来源单号、状态、版本与时间，禁止过度泄露联系人',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'READY' COMMENT '投递状态',
  `attempts` INT NOT NULL DEFAULT 0 COMMENT '发送次数',
  `max_attempts` INT NOT NULL DEFAULT 5 COMMENT '重试上限',
  `next_attempt_at` DATETIME(3) NOT NULL COMMENT '下次尝试',
  `claim_owner` VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '当前后台处理实例',
  `claim_token` VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '本次领取令牌，旧领取者不得更新新结果',
  `lease_until` DATETIME(3) NULL COMMENT '后台处理租约，与骑手持货权无关',
  `delivered_at` DATETIME(3) NULL COMMENT '来源确认接收时间',
  `last_http_status` SMALLINT NULL COMMENT '最后 HTTP 状态',
  `last_error` VARCHAR(1000) NULL COMMENT '脱敏失败原因',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '领取版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_external_callback_delivery_client_id_event_id` (`client_id`, `event_id`),
  KEY `ix_external_callback_delivery_status_next_attempt_at_id` (`status`, `next_attempt_at`, `id`),
  KEY `ix_external_callback_delivery_status_lease_until_id` (`status`, `lease_until`, `id`),
  KEY `ix_external_callback_delivery_client_id_order_id` (`client_id`, `order_id`),
  CONSTRAINT `ck_external_callback_delivery_1` CHECK (order_version >= 0 AND version >= 0),
  CONSTRAINT `ck_external_callback_delivery_2` CHECK (attempts >= 0 AND max_attempts > 0 AND attempts <= max_attempts),
  CONSTRAINT `ck_external_callback_delivery_3` CHECK (last_http_status IS NULL OR last_http_status BETWEEN 100 AND 599),
  CONSTRAINT `ck_external_callback_delivery_4` CHECK ((status = 'SENDING' AND claim_owner IS NOT NULL AND claim_token IS NOT NULL AND lease_until IS NOT NULL) OR (status <> 'SENDING' AND claim_owner IS NULL AND claim_token IS NULL AND lease_until IS NULL)),
  CONSTRAINT `ck_external_callback_delivery_5` CHECK (status <> 'DELIVERED' OR delivered_at IS NOT NULL),
  CONSTRAINT `ck_external_callback_delivery_6` CHECK (`status` IN ('READY','SENDING','DELIVERED','DEAD'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='P3 版本化履约回调重试';

-- 真实渠道扩展 | 支付与退款 | 真实渠道账单核对批次
CREATE TABLE `payment_reconciliation_batch` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `batch_no` VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '平台核对批次编号',
  `channel` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '账单来源渠道',
  `business_date` DATE NOT NULL COMMENT '渠道账单业务日期，按渠道日界线解释',
  `source_digest` BINARY(32) NOT NULL COMMENT '账单内容摘要，重复导入同内容不产生新批次',
  `source_object_ref` VARCHAR(500) NULL COMMENT '受控账单文件引用，不保存访问密钥',
  `status` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CREATED' COMMENT '核对状态',
  `total_rows` INT NOT NULL DEFAULT 0 COMMENT '已读账单行数',
  `matched_rows` INT NOT NULL DEFAULT 0 COMMENT '匹配行数',
  `discrepancy_rows` INT NOT NULL DEFAULT 0 COMMENT '差异行数',
  `started_at` DATETIME(3) NULL COMMENT '开始',
  `finished_at` DATETIME(3) NULL COMMENT '结束',
  `last_error` VARCHAR(1000) NULL COMMENT '脱敏导入/核对错误',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '批次并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_reconciliation_batch_batch_no` (`batch_no`),
  UNIQUE KEY `uk_payment_reconciliation_batch_channel_business_date_289c90a0d7` (`channel`, `business_date`, `source_digest`),
  KEY `ix_payment_reconciliation_batch_status_created_at_id` (`status`, `created_at`, `id`),
  CONSTRAINT `ck_payment_reconciliation_batch_1` CHECK (total_rows >= 0 AND matched_rows >= 0 AND discrepancy_rows >= 0),
  CONSTRAINT `ck_payment_reconciliation_batch_2` CHECK (matched_rows + discrepancy_rows <= total_rows),
  CONSTRAINT `ck_payment_reconciliation_batch_3` CHECK (version >= 0),
  CONSTRAINT `ck_payment_reconciliation_batch_4` CHECK (status NOT IN ('COMPLETED','FAILED') OR finished_at IS NOT NULL),
  CONSTRAINT `ck_payment_reconciliation_batch_5` CHECK (`status` IN ('CREATED','PROCESSING','COMPLETED','FAILED')),
  CONSTRAINT `ck_payment_reconciliation_batch_6` CHECK (status <> 'COMPLETED' OR matched_rows + discrepancy_rows = total_rows)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='真实渠道账单核对批次';

-- 真实渠道扩展 | 支付与退款 | 真实渠道账单差异与处理凭据
CREATE TABLE `payment_reconciliation_item` (
  `id` BIGINT NOT NULL AUTO_INCREMENT COMMENT '内部主键；API 按字符串传输',
  `batch_id` BIGINT NOT NULL COMMENT '核对批次',
  `line_no` INT NOT NULL COMMENT '批次内行号，含本地补充的渠道缺失条目',
  `transaction_type` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '支付或退款',
  `payment_id` BIGINT NULL COMMENT '能匹配的本地支付；本地缺失时为空',
  `refund_id` BIGINT NULL COMMENT '能匹配的本地退款',
  `channel_txn_no` VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NULL COMMENT '账单交易/退款号',
  `local_amount_cent` BIGINT NULL COMMENT '本地金额，缺失时为空',
  `statement_amount_cent` BIGINT NULL COMMENT '渠道金额，缺失时为空',
  `currency` CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'CNY' COMMENT '币种',
  `match_result` VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL COMMENT '一致、金额/状态不符、本地缺失或渠道缺失',
  `resolution_state` VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'OPEN' COMMENT '差异处理状态',
  `handled_by` BIGINT NULL COMMENT '人工处理运营',
  `resolution` VARCHAR(1000) NULL COMMENT '核实依据和处理结论，不能直接篡改收款事实',
  `resolved_at` DATETIME(3) NULL COMMENT '差异结束时间',
  `version` BIGINT NOT NULL DEFAULT 0 COMMENT '差异处理并发版本',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间，UTC',
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '最近修改时间，UTC',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_payment_reconciliation_item_batch_id_line_no` (`batch_id`, `line_no`),
  KEY `ix_payment_reconciliation_item_resolution_state_created_at_id` (`resolution_state`, `created_at`, `id`),
  KEY `ix_payment_reconciliation_item_payment_id` (`payment_id`),
  KEY `ix_payment_reconciliation_item_payment_id_refund_id` (`payment_id`, `refund_id`),
  KEY `ix_payment_reconciliation_item_handled_by` (`handled_by`),
  CONSTRAINT `ck_payment_reconciliation_item_1` CHECK (line_no > 0 AND version >= 0),
  CONSTRAINT `ck_payment_reconciliation_item_2` CHECK (local_amount_cent IS NULL OR local_amount_cent > 0),
  CONSTRAINT `ck_payment_reconciliation_item_3` CHECK (statement_amount_cent IS NULL OR statement_amount_cent > 0),
  CONSTRAINT `ck_payment_reconciliation_item_4` CHECK (local_amount_cent IS NOT NULL OR statement_amount_cent IS NOT NULL),
  CONSTRAINT `ck_payment_reconciliation_item_5` CHECK (currency = 'CNY'),
  CONSTRAINT `ck_payment_reconciliation_item_6` CHECK (transaction_type <> 'PAYMENT' OR refund_id IS NULL),
  CONSTRAINT `ck_payment_reconciliation_item_7` CHECK (match_result <> 'MATCHED' OR (local_amount_cent IS NOT NULL AND statement_amount_cent IS NOT NULL AND local_amount_cent = statement_amount_cent)),
  CONSTRAINT `ck_payment_reconciliation_item_8` CHECK (resolution_state = 'OPEN' OR (resolved_at IS NOT NULL AND resolution IS NOT NULL)),
  CONSTRAINT `ck_payment_reconciliation_item_9` CHECK (`transaction_type` IN ('PAYMENT','REFUND')),
  CONSTRAINT `ck_payment_reconciliation_item_10` CHECK (`match_result` IN ('MATCHED','AMOUNT_MISMATCH','STATUS_MISMATCH','LOCAL_MISSING','CHANNEL_MISSING')),
  CONSTRAINT `ck_payment_reconciliation_item_11` CHECK (`resolution_state` IN ('OPEN','RESOLVED','IGNORED'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='真实渠道账单差异与处理凭据';

-- 核心引用与循环引用，所有父表已经存在，始终保留外键检查。
ALTER TABLE `service_city` ADD CONSTRAINT `fk_service_city_1` FOREIGN KEY (`city_code`, `active_pricing_rule_id`) REFERENCES `pricing_rule` (`city_code`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `service_city` ADD CONSTRAINT `fk_service_city_2` FOREIGN KEY (`city_code`, `active_dispatch_policy_id`) REFERENCES `dispatch_policy` (`city_code`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `user_role` ADD CONSTRAINT `fk_user_role_1` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `user_role` ADD CONSTRAINT `fk_user_role_2` FOREIGN KEY (`granted_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `user_address` ADD CONSTRAINT `fk_user_address_1` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `user_address` ADD CONSTRAINT `fk_user_address_2` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_profile` ADD CONSTRAINT `fk_rider_profile_1` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_profile` ADD CONSTRAINT `fk_rider_profile_2` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_profile` ADD CONSTRAINT `fk_rider_profile_3` FOREIGN KEY (`reviewed_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_workload` ADD CONSTRAINT `fk_rider_workload_1` FOREIGN KEY (`rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_location_session` ADD CONSTRAINT `fk_rider_location_session_1` FOREIGN KEY (`rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `service_area` ADD CONSTRAINT `fk_service_area_1` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `service_area` ADD CONSTRAINT `fk_service_area_2` FOREIGN KEY (`published_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `pricing_rule` ADD CONSTRAINT `fk_pricing_rule_1` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `pricing_rule` ADD CONSTRAINT `fk_pricing_rule_2` FOREIGN KEY (`published_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_policy` ADD CONSTRAINT `fk_dispatch_policy_1` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_policy` ADD CONSTRAINT `fk_dispatch_policy_2` FOREIGN KEY (`published_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_quote` ADD CONSTRAINT `fk_delivery_quote_1` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_quote` ADD CONSTRAINT `fk_delivery_quote_2` FOREIGN KEY (`city_code`, `pricing_rule_id`, `rule_version`) REFERENCES `pricing_rule` (`city_code`, `id`, `rule_version`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_quote` ADD CONSTRAINT `fk_delivery_quote_3` FOREIGN KEY (`consumed_order_id`, `id`) REFERENCES `delivery_order` (`id`, `quote_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `quote_address` ADD CONSTRAINT `fk_quote_address_1` FOREIGN KEY (`quote_id`, `city_code`) REFERENCES `delivery_quote` (`id`, `city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `quote_address` ADD CONSTRAINT `fk_quote_address_2` FOREIGN KEY (`service_area_id`, `city_code`) REFERENCES `service_area` (`id`, `city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `external_client` ADD CONSTRAINT `fk_external_client_1` FOREIGN KEY (`owner_user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_order` ADD CONSTRAINT `fk_delivery_order_1` FOREIGN KEY (`quote_id`, `owner_user_id`, `city_code`) REFERENCES `delivery_quote` (`id`, `user_id`, `city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_order` ADD CONSTRAINT `fk_delivery_order_2` FOREIGN KEY (`city_code`, `dispatch_policy_id`) REFERENCES `dispatch_policy` (`city_code`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_order` ADD CONSTRAINT `fk_delivery_order_3` FOREIGN KEY (`source_client_id`, `source_system`, `owner_user_id`) REFERENCES `external_client` (`id`, `source_system`, `owner_user_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_order` ADD CONSTRAINT `fk_delivery_order_4` FOREIGN KEY (`id`, `active_assignment_id`, `assignment_epoch`) REFERENCES `delivery_assignment` (`order_id`, `id`, `epoch`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_order` ADD CONSTRAINT `fk_delivery_order_5` FOREIGN KEY (`id`, `paid_payment_id`) REFERENCES `payment_order` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_address` ADD CONSTRAINT `fk_order_address_1` FOREIGN KEY (`order_id`, `city_code`) REFERENCES `delivery_order` (`id`, `city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_address` ADD CONSTRAINT `fk_order_address_2` FOREIGN KEY (`service_area_id`, `city_code`) REFERENCES `service_area` (`id`, `city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_assignment` ADD CONSTRAINT `fk_delivery_assignment_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `delivery_assignment` ADD CONSTRAINT `fk_delivery_assignment_2` FOREIGN KEY (`rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_decision` ADD CONSTRAINT `fk_dispatch_decision_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_decision` ADD CONSTRAINT `fk_dispatch_decision_2` FOREIGN KEY (`policy_id`) REFERENCES `dispatch_policy` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_decision` ADD CONSTRAINT `fk_dispatch_decision_3` FOREIGN KEY (`selected_rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_offer` ADD CONSTRAINT `fk_dispatch_offer_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_offer` ADD CONSTRAINT `fk_dispatch_offer_2` FOREIGN KEY (`rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `dispatch_offer` ADD CONSTRAINT `fk_dispatch_offer_3` FOREIGN KEY (`order_id`, `dispatch_round`, `decision_id`) REFERENCES `dispatch_decision` (`order_id`, `dispatch_round`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_status_log` ADD CONSTRAINT `fk_order_status_log_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_status_log` ADD CONSTRAINT `fk_order_status_log_2` FOREIGN KEY (`order_id`, `assignment_id`) REFERENCES `delivery_assignment` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_return_request` ADD CONSTRAINT `fk_order_return_request_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_return_request` ADD CONSTRAINT `fk_order_return_request_2` FOREIGN KEY (`requested_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_return_request` ADD CONSTRAINT `fk_order_return_request_3` FOREIGN KEY (`reviewed_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `exception_case` ADD CONSTRAINT `fk_exception_case_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `exception_case` ADD CONSTRAINT `fk_exception_case_2` FOREIGN KEY (`order_id`, `assignment_id`) REFERENCES `delivery_assignment` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `exception_case` ADD CONSTRAINT `fk_exception_case_3` FOREIGN KEY (`reporter_user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `exception_case` ADD CONSTRAINT `fk_exception_case_4` FOREIGN KEY (`handler_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_record` ADD CONSTRAINT `fk_custody_record_1` FOREIGN KEY (`order_id`, `assignment_id`, `assignment_epoch`) REFERENCES `delivery_assignment` (`order_id`, `id`, `epoch`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_record` ADD CONSTRAINT `fk_custody_record_2` FOREIGN KEY (`actor_user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_record` ADD CONSTRAINT `fk_custody_record_3` FOREIGN KEY (`order_id`, `return_request_id`) REFERENCES `order_return_request` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_order` ADD CONSTRAINT `fk_payment_order_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `refund_order` ADD CONSTRAINT `fk_refund_order_1` FOREIGN KEY (`payment_id`, `channel`) REFERENCES `payment_order` (`id`, `channel`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `refund_order` ADD CONSTRAINT `fk_refund_order_2` FOREIGN KEY (`requested_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_callback_inbox` ADD CONSTRAINT `fk_payment_callback_inbox_1` FOREIGN KEY (`payment_id`, `channel`) REFERENCES `payment_order` (`id`, `channel`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_callback_inbox` ADD CONSTRAINT `fk_payment_callback_inbox_2` FOREIGN KEY (`payment_id`, `refund_id`) REFERENCES `refund_order` (`payment_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_channel_attempt` ADD CONSTRAINT `fk_payment_channel_attempt_1` FOREIGN KEY (`payment_id`) REFERENCES `payment_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_channel_attempt` ADD CONSTRAINT `fk_payment_channel_attempt_2` FOREIGN KEY (`payment_id`, `refund_id`) REFERENCES `refund_order` (`payment_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `location_point` ADD CONSTRAINT `fk_location_point_1` FOREIGN KEY (`rider_id`, `session_id`) REFERENCES `rider_location_session` (`rider_id`, `session_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `receiver_access` ADD CONSTRAINT `fk_receiver_access_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `receiver_access` ADD CONSTRAINT `fk_receiver_access_2` FOREIGN KEY (`issued_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_evaluation` ADD CONSTRAINT `fk_order_evaluation_1` FOREIGN KEY (`order_id`, `user_id`) REFERENCES `delivery_order` (`id`, `owner_user_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_evaluation` ADD CONSTRAINT `fk_order_evaluation_2` FOREIGN KEY (`order_id`, `assignment_id`, `rider_id`) REFERENCES `delivery_assignment` (`order_id`, `id`, `rider_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `inbox_notification` ADD CONSTRAINT `fk_inbox_notification_1` FOREIGN KEY (`user_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `inbox_notification` ADD CONSTRAINT `fk_inbox_notification_2` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `notification_delivery` ADD CONSTRAINT `fk_notification_delivery_1` FOREIGN KEY (`inbox_notification_id`) REFERENCES `inbox_notification` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_weight_adjustment` ADD CONSTRAINT `fk_order_weight_adjustment_1` FOREIGN KEY (`order_id`) REFERENCES `delivery_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_weight_adjustment` ADD CONSTRAINT `fk_order_weight_adjustment_2` FOREIGN KEY (`order_id`, `assignment_id`) REFERENCES `delivery_assignment` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `order_weight_adjustment` ADD CONSTRAINT `fk_order_weight_adjustment_3` FOREIGN KEY (`order_id`, `paid_payment_id`) REFERENCES `payment_order` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_route` ADD CONSTRAINT `fk_rider_route_1` FOREIGN KEY (`rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_route` ADD CONSTRAINT `fk_rider_route_2` FOREIGN KEY (`city_code`) REFERENCES `service_city` (`city_code`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_route` ADD CONSTRAINT `fk_rider_route_3` FOREIGN KEY (`id`, `current_plan_id`, `route_version`) REFERENCES `rider_route_plan` (`route_id`, `id`, `route_version`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `rider_route_plan` ADD CONSTRAINT `fk_rider_route_plan_1` FOREIGN KEY (`route_id`) REFERENCES `rider_route` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `route_stop` ADD CONSTRAINT `fk_route_stop_1` FOREIGN KEY (`route_plan_id`) REFERENCES `rider_route_plan` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `route_stop` ADD CONSTRAINT `fk_route_stop_2` FOREIGN KEY (`order_id`, `assignment_id`) REFERENCES `delivery_assignment` (`order_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_handover` ADD CONSTRAINT `fk_custody_handover_1` FOREIGN KEY (`order_id`, `from_assignment_id`, `from_rider_id`, `expected_epoch`) REFERENCES `delivery_assignment` (`order_id`, `id`, `rider_id`, `epoch`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_handover` ADD CONSTRAINT `fk_custody_handover_2` FOREIGN KEY (`to_rider_id`) REFERENCES `rider_profile` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_handover` ADD CONSTRAINT `fk_custody_handover_3` FOREIGN KEY (`order_id`, `to_assignment_id`, `to_rider_id`) REFERENCES `delivery_assignment` (`order_id`, `id`, `rider_id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `custody_handover` ADD CONSTRAINT `fk_custody_handover_4` FOREIGN KEY (`operator_id`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `external_order_request` ADD CONSTRAINT `fk_external_order_request_1` FOREIGN KEY (`client_id`) REFERENCES `external_client` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `external_order_request` ADD CONSTRAINT `fk_external_order_request_2` FOREIGN KEY (`client_id`, `order_id`, `source_order_no`) REFERENCES `delivery_order` (`source_client_id`, `id`, `source_order_no`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `external_callback_delivery` ADD CONSTRAINT `fk_external_callback_delivery_1` FOREIGN KEY (`client_id`) REFERENCES `external_client` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `external_callback_delivery` ADD CONSTRAINT `fk_external_callback_delivery_2` FOREIGN KEY (`client_id`, `order_id`) REFERENCES `delivery_order` (`source_client_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_reconciliation_item` ADD CONSTRAINT `fk_payment_reconciliation_item_1` FOREIGN KEY (`batch_id`) REFERENCES `payment_reconciliation_batch` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_reconciliation_item` ADD CONSTRAINT `fk_payment_reconciliation_item_2` FOREIGN KEY (`payment_id`) REFERENCES `payment_order` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_reconciliation_item` ADD CONSTRAINT `fk_payment_reconciliation_item_3` FOREIGN KEY (`payment_id`, `refund_id`) REFERENCES `refund_order` (`payment_id`, `id`) ON DELETE RESTRICT ON UPDATE RESTRICT;
ALTER TABLE `payment_reconciliation_item` ADD CONSTRAINT `fk_payment_reconciliation_item_4` FOREIGN KEY (`handled_by`) REFERENCES `app_user` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT;

SELECT DATABASE() AS database_name, COUNT(*) AS application_table_count FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE';
