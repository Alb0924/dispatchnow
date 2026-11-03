# 本次代码修复验证记录

日期：2026 年 11 月 3 日。当前执行环境为 Linux，JDK 21 / Maven 3.9.11。用户实际环境为 Windows 11 + VMware / CentOS 7。两者分别记录，不将隔离联调写成已直连用户虚拟机。

## 构建与真实服务联调

依据用户 test.txt 中的版本，使用官方包/源码构造同版本独立服务：MySQL 8.0.46、Redis 8.10.3、RabbitMQ 4.2.3。Redis 无密码，RabbitMQ 使用 delivery_now vhost，数据库名为 project01。主机地址与端口使用隔离实例值，未连接用户的私网 IP。

| 检查 | 实际结果 |
|---|---|
| 普通 clean verify | 成功，2 项 BootstrapHttpTest 通过 |
| infrastructure-it + dispatchnow.it.profile=vm | 2 项启动测试 + 6 项 InfrastructureIT，0 失败、0 错误、0 跳过 |
| MySQL 8.0.46 结构兼容 | 已批准完整 DDL 在隔离空 project01 建成 46 张表 |
| 数据库连接 | 使用非 root 应用账号执行查询，库名与 UTC 会话检查通过 |
| 表名检查 | 46 张批准业务表均存在；允许额外迁移元数据表 |
| Redis | 无密码连接，随机键读写与 TTL 校验成功，随后清理 |
| RabbitMQ | 非默认 delivery_now vhost 的临时队列收发、清理成功 |
| 最终可执行 JAR | vm profile + 根目录 .env 启动成功，三项连接均 UP |
| 管理端点 | /actuator/env 为 404；健康 HTTP 不泄露详情 |
| 缺配置 | vm 模式缺少根目录 .env / 工作目录错误时，在启动阶段失败 |
| 自动改库边界 | 本次启动与测试没有新增 Flyway 历史或业务账户记录 |
| Compose | 原附件 config --quiet 失败；修复后使用 .env.example 解析通过 |

实际 Maven profile 命令：`-Pinfrastructure-it -Ddispatchnow.it.profile=vm clean verify`。2 项独立启动测试不连接外部服务；6 项集成测试选择 vm，确保测到新增的运行配置。

## 打包后的故障与恢复

应用保持运行，分别停止一个真实依赖，再启动恢复：

| 依赖 | 基础设施故障 HTTP | readiness | 恢复 HTTP |
|---|---|---|---|
| mysql | 503 | 503 | 200 |
| redis | 503 | 503 | 200 |
| rabbitmq | 503 | 200 | 200 |

三项中断期间 liveness 均为 200，依赖恢复后应用无需重启即可重新连接。以上不是订单、退款或 MQ 补发功能的故障验收。

## 未在本次环境执行

- Windows 11 到 VMware 网卡、CentOS 防火墙和实际账户授权的现场复核。
- 可选 Compose 的容器启动、端口发布和数据卷验证。
- 现有数据库的完整字段/索引差异对比、备份恢复、Flyway baseline 与版本升级。
- 仍未实现的业务接口、权限、状态机和端到端闭环。

用户提供的旧版 2 + 5 项本机通过记录作为此前环境信息保留；修复版本机复核按根 README 执行 2 + 6 项。测试与临时服务进程均已清理，真实 .env 不包含在归档中。

历史第 02 步验证见 archive/VERIFICATION_STEP_02.md。
