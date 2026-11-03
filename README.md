# DispatchNow 同城即时取送平台

项目按 v1.0 采用模块化单体，唯一启动应用是 dispatchnow-app。当前已有工程骨架、中间件连接和健康检查；project01 的 46 张表由用户手工创建。业务接口仍按任务表逐步实现。

本次修订适配 **Windows 11 运行后端，VMware / CentOS 7 虚拟机运行 MySQL、Redis、RabbitMQ**。使用已有虚拟机服务即可按以下步骤运行 Java 工程。

## 1. 环境和版本

| 项目 | 当前使用 / 来源 |
|---|---|
| 后端 | Windows 11，JDK 21 |
| 框架 / 构建 | Spring Boot 4.1.2，Maven Wrapper 3.3.4，Maven 3.9.11 |
| 虚拟机地址 | 自检记录为 192.168.117.129；变动时只修改自己的 .env |
| MySQL | 自检记录为 8.0.46，3306，数据库 project01 |
| Redis | 自检记录为 8.10.3，6379，无密码 |
| RabbitMQ | 自检记录为 4.2.3，AMQP 5672，管理界面 15672，vhost delivery_now |
| 可选同机 Compose | MySQL 8.4.8 / Redis 8.2.4 / RabbitMQ 4.2.5，保留独立的固定镜像基线 |

虚拟机版本来源为用户提供的 test.txt，不把它写成本次从用户虚拟机再次探测的结果。可选 Compose 环境与当前 VM 环境是两套启动方式，版本可以并存；验证结果分别记录。

## 2. 在 Windows 准备配置

所有命令在包含 pom.xml、mvnw.cmd 的工程根目录执行。已有自己的 .env 时保留原文件，核对 .env.vm.example 中的键即可。

只有新目录尚无 .env 时，执行：

```powershell
Copy-Item .env.vm.example .env
notepad .env
```

填入自己的 MySQL 与 RabbitMQ 密码。模板里的 REPLACE_WITH... 必须替换。Redis 无密码时保留一行 `REDIS_PASSWORD=`，不是字符串引号，也不填本机 Compose 的示例密码。

文件使用 UTF-8 和简单 KEY=value，不加引号、export 或行尾注释；注释放在独立行。这里显式按 Java properties 导入，不是完整 dotenv 语法。真实 .env 已忽略，源码包不包含该文件。示例中的虚拟机 IP 和用户名不是密码。

vm 配置必须读到根目录 .env，并要求填写三项服务的主机、数据库账号及 RabbitMQ vhost；缺少文件会在启动阶段失败。操作系统环境变量、JVM 属性或启动参数仍可能覆盖文件值，.env 不是唯一优先级来源。

## 3. 验证 Windows 到虚拟机的网络

```powershell
java -version
Test-NetConnection 192.168.117.129 -Port 3306
Test-NetConnection 192.168.117.129 -Port 6379
Test-NetConnection 192.168.117.129 -Port 5672
```

TcpTestSucceeded=True 仅证明 TCP 端口可达，不证明账号、数据库或 vhost 授权正确。主机地址按自己的 .env 替换。

连接失败时在虚拟机检查服务监听、Docker 已发布端口和防火墙规则。若 Docker 端口只发布到虚拟机 127.0.0.1，Windows 无法通过虚拟机网卡地址访问。对已有服务先检查，不通过重建容器或删除卷排查。

## 4. 构建、连接验收与启动

先运行不连接中间件的工程测试：

```powershell
.\mvnw.cmd -B -ntp clean verify
```

再针对已有虚拟机运行连接验收：

```powershell
.\mvnw.cmd -B -ntp -Pinfrastructure-it "-Ddispatchnow.it.profile=vm" clean verify
```

第一条执行 2 项 BootstrapHttpTest；第二条额外执行 6 项 InfrastructureIT。新增一项只读检查：当前数据库必须包含已批准的 46 张业务表，允许将来新增 flyway_schema_history。它不比较全部列和索引，不能代替 Flyway 接管前的结构核对。

连接测试还会执行 SELECT 1、核对数据库与 UTC 会话，读写一个随机 Redis 键并检查 TTL，声明/收发/删除随机临时队列，以及检查 HTTP 探针。缓存键和队列在 finally 中清理，测试不会修改业务表中的记录或自动建表。

构建成功后启动：

```powershell
java -jar .\dispatchnow-app\target\dispatchnow-app-0.1.0-SNAPSHOT.jar --spring.profiles.active=vm
```

访问 <http://127.0.0.1:8080/actuator/health/infrastructure>，db、redis、rabbit 应全部为 UP。Ctrl+C 退出应用。

在 IDEA 导入根 pom.xml，Project SDK 与 Maven Runner 均为 JDK 21，运行 DispatchNowApplication：Active profiles 设置 vm，Working directory 设置为工程根目录。不要将源码子模块目录或 target/classes 设为工作目录。

Linux / macOS 将 .\mvnw.cmd 替换为 ./mvnw，路径改为正斜杠，启动参数保持相同。

## 5. 探针和配置定位

| 地址 | 含义 |
|---|---|
| /actuator/health | 全部健康指标汇总，不显示组件详情 |
| /actuator/health/infrastructure | 三项实际连接状态，隐藏账号和异常详情 |
| /actuator/health/readiness | 应用已就绪且 MySQL / Redis 可用 |
| /actuator/health/liveness | 应用自身存活，不因中间件故障变为 DOWN |
| /actuator/env | 未开放，返回 404 |

MySQL 或 Redis 故障：整体健康和 readiness 为 503。只有 RabbitMQ 故障：整体健康为 503，readiness 可为 200，为后续 Outbox 保留恢复空间。readiness 只是状态信号，不会自动拦截直连普通请求。

| 现象 | 优先检查 |
|---|---|
| vm 启动提示缺少 .env | 文件是否位于工程根目录，IDEA 工作目录是否正确 |
| MySQL Access denied | 应用实际账号/host 授权、密码、project01 权限；本地开发账号不必与镜像默认名一致 |
| Unknown database | MYSQL_DATABASE=project01，连接到的是否为正确虚拟机 |
| Redis NOAUTH / WRONGPASS / DENIED | 密码是否确实为空，服务端 ACL、保护模式与监听地址 |
| RabbitMQ ACCESS_REFUSED | 账户、密码和 delivery_now vhost 及权限；AMQP 使用 5672 |
| 端口可达但错误连接到旧地址 | 核对系统环境变量是否覆盖 .env；检查宿主机和虚拟机的网络含义 |
| 表检查失败 | 确认选中 project01，核对缺失表，按 database/inspect_existing.sql 导出元数据 |

## 6. 可选的同机 Compose

compose.yaml 仅用于另一套同机开发环境，宿主机端口绑定 127.0.0.1；容器自己的 MySQL 健康检查也使用容器内 127.0.0.1。Windows 连接已有 VM 的流程不需要执行这一节。

明确使用本机示例配置校验和启动：

```bash
docker compose --env-file .env.example -f compose.yaml config --quiet
docker compose --env-file .env.example -f compose.yaml up -d --wait --wait-timeout 180
```

首次本机容器会创建空 project01；在该独立空库导入 database/reference/project01_full.sql 后才具备 46 张业务表。不要对已有虚拟机库再次执行全量初始化。该参照脚本没有 DROP DATABASE 或删除业务表的语句，并含空库保护。

要让应用连接这套同机服务，需要在自己的 .env 使用 .env.example 中的同机地址/账号，并选择 dev 配置。切换前自行保留原 VM 配置。已有命名卷里的账号不会因修改初始化变量自动更新。

## 7. 下一步

现在的重点是接管已有数据库的迁移历史：只读核对结构、保存备份、显式 baseline 到 V1、验证空库 V1 与后续 V2。然后实现统一响应/错误/traceId，再做注册登录、角色和地址。

详见 [docs/NEXT_TASKS.md](docs/NEXT_TASKS.md)、[docs/CODE_REVIEW.md](docs/CODE_REVIEW.md) 和 [docs/VERIFICATION.md](docs/VERIFICATION.md)。架构继续保持 v1.0 模块化单体。
