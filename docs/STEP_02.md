# 第 02 步：中间件连接与健康检查

本文件保留第 02 步历史设计。当前 Windows + VM 运行方式、6 项连接测试和修复结论以根 README、CODE_REVIEW.md 与 VERIFICATION.md 为准。

项目定位与 v1.0 架构保持一致。本步为后面的用户、订单和支付功能准备运行基础。

## 修改位置

| 文件 | 作用 |
|---|---|
| compose.yaml | 固定版本与摘要，声明三项服务、端口、数据卷和健康检查 |
| .env.example | Compose 与应用共用的本地配置 |
| dispatchnow-app/pom.xml | JDBC、MySQL 驱动、Redis、AMQP 和可选集成测试 |
| application.yml | 连接池、超时、管理端点边界与探针分组 |
| application-dev.yml | 导入根目录 .env，配置真实连接和开发健康分组 |
| application-test.yml | 为原有工程启动测试隔离外部依赖 |
| InfrastructureIT.java | 真实查询、缓存读写、消息收发与 HTTP 验收 |

四个业务模块继续生成普通 JAR，装配进 dispatchnow-app。模块间不使用 HTTP / RPC，也没有新增网关或注册中心。

## 三项依赖的职责

MySQL 保存业务事实，后续用户、配送单、报价快照、指派、骑手容量与 Outbox 都在此持久化。需要关联维护的业务约束通过同一个数据源中的本地事务实现。应用使用专属数据库账号。

Redis 为后续会话、限流、骑手最新位置与 GEO 查询提供基础。位置与派单候选需要时效检查；缓存不能取代订单状态和容量事务。本步仅验证连接、带 TTL 的写入与读取。

RabbitMQ 为后续异步事件与通知提供消息通道。本步验证 AMQP 连接及临时队列收发。业务拓扑、可靠发布、消费幂等和死信在实际使用时加入，当前尚未实现消息可靠性。

## 配置如何生效

1. 将 .env.example 复制为项目根目录的 .env。
2. Compose 读取初始化账号与端口变量。
3. dev 配置通过 spring.config.import 显式导入同一文件。
4. 从根目录运行 JAR；集成测试也固定该工作目录。

JVM 不原生支持 dotenv。本项目按 Java properties 导入，使用两边均识别的简单 `KEY=value`，不加引号、export 或行尾注释。已有 .env 不应被示例覆盖。应用支持操作系统环境变量和启动参数覆盖。

镜像固定补丁版本与摘要；升级时两者一起更新并重新验证。命名数据卷会跨容器重建保留。MySQL、RabbitMQ 的初始化账号只在空数据目录首次启动时生效。

MySQL 使用 utf8mb4，服务端与 JDBC 会话使用 UTC。连接池上限 10、最少空闲 0，获取连接最多等待 2 秒；驱动连接 2 秒、socket 读取 3 秒。Redis 连接和命令各 2 秒，RabbitMQ 连接 2 秒、通道 RPC 3 秒。多项健康检查的总耗时可能超过单项超时。

连接池不在启动时强制预取连接，进程启动后可以报告实际 DOWN 状态。下一步加入 Flyway 后，迁移需要可用数据库，应重新验证启动行为。

## 健康探针

所有路径以 /actuator/health 开头：

| 场景 | 整体及 /infrastructure | /readiness | /liveness |
|---|---|---|---|
| 三项均正常 | 200 UP | 200 UP | 200 UP |
| MySQL 不可用 | 503 DOWN，db 为 DOWN | 503 DOWN | 200 UP |
| Redis 不可用 | 503 DOWN，redis 为 DOWN | 503 DOWN | 200 UP |
| 只有 RabbitMQ 不可用 | 503 DOWN，rabbit 为 DOWN | 200 UP | 200 UP |

readiness 还要求应用已进入接收流量状态。MySQL、Redis 将直接参与数据库业务与会话，因此纳入核心就绪条件。RabbitMQ 是异步通道，按后续本地事务与 Outbox 的设计，暂不纳入 readiness。当前尚没有 Outbox，实现恢复能力后仍需单独验证。

liveness 只检查应用自身状态，避免外部故障导致反复重启。readiness 是状态信号，不会拦截普通请求；部署时由负载均衡器读取，本步没有负载均衡器。

除 health 外，不开放 env、configprops 等管理端点。dev 的基础设施与就绪分组只显示组件状态，始终隐藏详情，失败时也不返回 JDBC 地址或异常堆栈。

## 测试与故障复核

普通 clean verify 执行 2 项 BootstrapHttpTest，只证明骨架能启动。添加 Maven profile `-Pinfrastructure-it` 后额外执行 5 项真实测试：

1. 使用应用数据库账号查询 SELECT 1、当前数据库和会话时区。
2. 创建随机 Redis 键，验证读回值与 TTL，最后清理。
3. 声明随机临时队列，发送并接收消息，最后删除队列。
4. HTTP 查询 infrastructure 分组，检查三个组件均 UP 且无详情。
5. 检查 readiness、liveness、整体健康和 /actuator/env 的边界。

测试不建业务表、不声明业务消息拓扑。Redis 测试检查 TTL 被设置，没有等待 30 秒再观察过期。

本机可以在应用保持运行时复核故障与恢复：

```bash
docker compose stop mysql
# 访问探针，核对矩阵
docker compose up -d --wait --wait-timeout 180 mysql
# 等待整体恢复 UP，再分别对 redis、rabbitmq 重复上述操作
```

每次恢复健康后再测试下一项。Windows 可直接用浏览器访问，或用 `curl.exe -i URL` 查看 HTTP 状态。健康检查不会自动清库、清缓存或补发业务消息。

建议依次阅读 compose.yaml、application-dev.yml、application.yml 和 InfrastructureIT，再运行 README 的完整命令。实际执行情况见 VERIFICATION.md。

下一步接入 Flyway 与首批表、索引，验证空库迁移与重复启动后再实现业务接口。后续任务仍按总表逐步推进。

## 官方参考

- [Spring Boot 健康检查与探针](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html)
- [Spring Boot 外部配置](https://docs.spring.io/spring-boot/reference/features/external-config.html)
- [MySQL 官方容器与初始化变量](https://hub.docker.com/_/mysql)
- [Redis 官方容器](https://hub.docker.com/_/redis)
- [RabbitMQ 官方容器](https://hub.docker.com/_/rabbitmq)
- [Docker Compose up](https://docs.docker.com/reference/cli/docker/compose/up/)
