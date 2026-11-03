# Windows + VMware 环境代码复核

日期：2026 年 11 月 3 日。依据用户上传的 DispatchNow.zip 和 test.txt，自检记录作为环境信息来源；本次没有从外部直接登录用户的 Windows 或 CentOS 虚拟机。

## 结论

需要修复的是运行配置、Compose 和工程文档衔接。Java 工程仍是模块化单体骨架，原有 JDBC / Redis / AMQP 连接方式可以用于 Windows 通过 TCP 访问虚拟机，不需要改成微服务，也不需要把后端搬到虚拟机。

用户附件中的源文件与上一轮工程相比，变化集中在 .env.example 和 compose.yaml；压缩包没有真实 .env。自检记录称只改 .env，不能据此确认该记录对应附件中的全部配置。也不能因此否定用户本机曾通过的 2 + 5 项测试，只是本次归档不包含那份真实配置。

## 发现和处理

| 项目 | 发现 | 本次处理 |
|---|---|---|
| Compose 默认值语法 | MySQL 组使用 ${VAR:default}，属于 Spring 风格，不是 Compose 默认值语法；官方 CLI 实际解析失败 | 改为 ${VAR:-default}，修复后 config --quiet 通过 |
| Compose 宿主机地址 | MySQL 端口发布硬编码虚拟机网卡 IP，移到没有该 IP 的 Docker 宿主机无法绑定 | 可选同机 Compose 统一绑定宿主机 127.0.0.1；用户 VM 主流程直接连接既有服务 |
| 容器健康检查地址 | MySQL 自检绕到虚拟机宿主机地址，依赖端口映射/网络回环 | 检查容器自身 127.0.0.1:3306 和真实应用账号/库 |
| 混合环境模板 | 原样例 MySQL/Redis 指向本机，RabbitMQ 指向虚拟机；账号与 Redis 认证也和报告不一致 | 分为同机 .env.example 和已有 VM 的 .env.vm.example |
| 真实凭据 | 原 .env.example 混入个人环境的密码 | 示例恢复为公开本机样例；VM 模板只含密码占位，真实 .env 不打包 |
| 数据库名 | 源码与集成测试缺省仍是 dispatchnow | 统一缺省 project01，仍允许 .env 明确配置 |
| VM 缺配置的表现 | 原 dev 可在 .env 缺失/不完整时回退本机，容易连错实例 | 新增 vm 配置，要求根目录 .env 和必要连接键；保留 dev 供同机使用 |
| 集成测试配置 | @ActiveProfiles("dev") 固定选择 dev，无法真实验收新 VM 配置 | Failsafe 用 dispatchnow.it.profile 选择环境，默认 dev，VM 指定 vm；不污染独立启动测试 |
| 数据库就绪范围 | SELECT 1 与健康 UP 不能证明 project01 已有需要的业务表 | 新增第 6 项 IT，只读校验 46 张批准业务表存在，允许后续迁移历史表 |
| 运行说明 | 原主流程要求在 Windows 启动 Compose，与现有部署方式不符 | README 主流程改为 Windows Java/Maven 连接已有 VM，补充 IDEA、端口和认证排查 |
| 归档内容 | 上传包包含 .idea、target 和旧编译配置 | 交付源码包排除这些目录，构建从 clean 开始 |

没有修改用户数据库里的表、账号、密码或数据；也没有修改 Spring Boot / JDK / 四个业务模块的架构与版本。VM 模板中不需要 MYSQL_ROOT_PASSWORD，应用只使用自身 MySQL 登录配置。

## 对 DeepSeek 自检结论的判断

### 非空数据库没有 Flyway 历史：需要处理，但不需要删库

该现象确实会阻止直接按默认设置执行首次 migrate。解决方法不止“删库重放”：Flyway 的 baseline 正是用于接管已有数据库。核对现有结构与代码里的 V1 相符后，显式 baseline 到版本 1，V2 及以后的迁移仍会被执行、记录和校验。

因此“baseline 后 46 张表永远不在版本管理里”“等于放弃迁移价值”的表述不准确。准确边界是：已有库不重放 V1；baseline 不替人验证既有结构，也不产生一份曾执行 V1 的虚构记录。V1 仍需保留在源码中并在空库测试，未来修改通过 V2/V3 管理。

本项目采用“先核对、再显式基线”的下一步方案，不把 baseline-on-migrate=true 开为普通启动默认值。现有库保留，DDL 参照和只读元数据脚本已放 database/。

### 版本不同：要标明来源和验证，不必为了对齐文档重装服务

README 原先列的是可选 Compose 的验证基线；用户 VM 是另一套环境。二者可以同时保留并分别标注。兼容性以实际驱动和服务验证为依据，不能只把版本号替换成一致就算完成。

本次按自检报告的 MySQL 8.0.46、Redis 8.10.3、RabbitMQ 4.2.3 构造了隔离的 Linux 服务验证环境。它可以验证相同协议版本下的应用连接与配置，但不能代替 Windows 到 VM 的网络、防火墙、端口发布和实际授权检查。实际结果见 VERIFICATION.md。

### 7 项测试通过不等于全部工程配置都正确

Maven 不解析 Compose，所以即使启动与连接测试通过，Compose 语法仍可能错误。本次分别执行原配置/修复配置的官方 Compose CLI 解析，确实观察到原文件失败、修复后通过。

数据库表名检查也不等于完整结构一致。下一步 baseline 前要比较列、默认值、索引、外键和 CHECK；当前测试不会自动基线化或清空数据库。

## 保留的设计

MySQL 保存业务事实，Redis 保留缓存/位置，RabbitMQ 承担后续异步事件；单启动入口和本地事务边界不变。健康端点继续隐藏敏感详情，liveness 与外部依赖分离。当前没有业务 API，因此本次没有宣称订单、支付或派单闭环已经实现。

## 官方依据

- [Docker Compose 变量插值](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)：${VAR:-default} 等语法。
- [Docker 端口发布](https://docs.docker.com/engine/network/port-publishing/)：发布地址属于 Docker 宿主机的网卡。
- [Spring Boot 外部配置](https://docs.spring.io/spring-boot/reference/features/external-config.html)：文件、环境变量和启动参数的优先级。
- [Flyway baseline](https://documentation.red-gate.com/fd/baseline-277578867.html)：接管现有数据库的版本起点。
- [Flyway baseline-on-migrate](https://documentation.red-gate.com/fd/flyway-baseline-on-migrate-setting-277578974.html)：自动基线的行为与默认关闭。
