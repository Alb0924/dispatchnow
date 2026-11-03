# DispatchNow 验证记录

## 第 02 步：中间件连接与健康检查

日期：2026 年 11 月 2 日，Asia/Shanghai。此处区分实际执行通过的检查与尚未执行的容器检查。

### 执行环境

Linux / Ubuntu 24.04，JDK 21，Spring Boot 4.1.2，Maven 3.9.11 / Wrapper 3.3.4。当前环境不能运行 Docker 容器，实际联调使用独立本机进程运行同版本服务：

| 服务 | 实际版本 | 来源 |
|---|---|---|
| MySQL | 8.4.8 | MySQL 官方 Linux 二进制包 |
| Redis | 8.2.4 | Redis 官方源码标签，本机编译 |
| RabbitMQ | 4.2.5 | RabbitMQ 官方通用 Unix 包，Erlang 27.3.4.8 |

验证时使用单独的数据目录、应用账号、非默认本地端口和测试密码。未使用其他项目的数据库或业务代码。测试配置经根目录 .env 导入，故实际连接同时验证了配置共享路径。

### 构建与测试结果

执行 Maven Wrapper 的 `-Pinfrastructure-it clean verify`，父工程与五个子模块全部构建成功：

| 检查 | 结果 |
|---|---|
| BootstrapHttpTest | 2 项通过，0 失败，0 错误，0 跳过 |
| InfrastructureIT | 5 项通过，0 失败，0 错误，0 跳过 |
| MySQL | 使用应用账号查询成功，数据库为 dispatchnow，JDBC 会话时区 +00:00 |
| Redis | 独立键写入、读回、TTL 检查成功，finally 清理 |
| RabbitMQ | 临时队列声明、发送、接收、删除成功 |
| 基础设施健康分组 | db、redis、rabbit 均为 UP，不包含 details |
| 管理端点边界 | /actuator/env 返回 404；整体健康隐藏组件详情 |
| 打包启动 | Java 21 运行最终可执行 JAR，使用同一 .env，HTTP 验收通过 |
| 进程清理 | 打包应用和三项测试服务均已关闭 |

实际解析的依赖版本：HikariCP 7.0.2、MySQL Connector/J 9.7.0、Lettuce 7.5.2.RELEASE、Rabbit Java Client 5.30.0、Spring Rabbit 4.1.2。它们由 Boot BOM 管理，已随上述实际服务联调验证。

### 打包后的故障与恢复

应用保持运行，依次终止一个真实依赖进程，再用原数据目录重启。每项恢复后确认全部 UP，再测试下一项。以下状态均为实际 HTTP 观察值：

| 场景 | 整体健康 | infrastructure | readiness | liveness | 依赖恢复后 |
|---|---|---|---|---|---|
| 正常 | 200 UP | 200 UP | 200 UP | 200 UP | — |
| MySQL 停止 | 503 DOWN | 503 DOWN，只有 db DOWN | 503 DOWN | 200 UP | 全部恢复 200 UP |
| Redis 停止 | 503 DOWN | 503 DOWN，只有 redis DOWN | 503 DOWN | 200 UP | 全部恢复 200 UP |
| RabbitMQ 停止 | 503 DOWN | 503 DOWN，只有 rabbit DOWN | 200 UP | 200 UP | 全部恢复 200 UP |

三次均无需重启应用。故障响应没有暴露异常详情。检查范围为连接、探针与重连，不包含尚未实现的订单、支付、消息补发或消费恢复。

### Compose 检查与剩余验收

已经使用官方 Compose CLI v2.39.4 执行 `config --quiet`，配置解析与变量插值校验通过。三个镜像标签与官方多平台摘要已核对，compose.yaml 同时固定标签和摘要。

**当前环境未执行 Docker Compose up。** 因此不宣称容器启动、容器内健康命令、端口映射和命名数据卷持久化已经通过运行验收。原生服务联调不能取代这些容器检查。任务总表将第 02 步保留“进行中”：代码与实际连接已完成，尚待目标机器完成下面的验收。

在安装并启动 Docker 的机器上，从项目根目录依次执行：

1. 按 README 准备 .env，运行 `docker compose up -d --wait --wait-timeout 180`。
2. `docker compose ps` 确认三项服务均 healthy。
3. 运行 `./mvnw -Pinfrastructure-it clean verify`；Windows 使用 mvnw.cmd。应有 2 + 5 项测试通过。
4. 运行 JAR，按 STEP_02.md 逐项 stop / up，核对故障矩阵。
5. 在自己的测试库 / 缓存 / 队列创建一份可丢弃数据，执行不带 -v 的 down，再 up，确认数据保留；随后清理测试数据。

这些操作不包含自动清库。Windows 与 macOS 的命令已经提供，本次实际执行的平台为 Linux。

## 第 01 步：历史验收

第 01 步已完成工程骨架、Wrapper、Java 21 编译、随机端口 HTTP 测试和打包 JAR 启动。

| 检查 | 当时结果 |
|---|---|
| clean verify | 父工程与五个子模块全部 BUILD SUCCESS |
| HTTP 测试 | 2 项通过，0 失败，0 错误，0 跳过 |
| 健康端点 | HTTP 200，status=UP，不包含组件详情 |
| 管理端点 | /actuator/env 返回 404 |
| Java 字节码 | 启动类 major 65，对应 Java 21 |
| 模块装配 | 可执行 JAR 包含四个业务模块的普通 JAR |
| 唯一入口 | 只有 DispatchNowApplication 提供 main 方法 |

第 01 步没有中间件连接。当前源码的运行与测试方式以 README 和第 02 步记录为准。
