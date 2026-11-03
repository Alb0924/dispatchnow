# 第 01 步 工程骨架与启动验收

本文件保留第 01 步的历史交付说明。当前启动方式以根目录 README.md 和 STEP_02.md 为准。

本步目标是得到一个可以在 JDK 21 下构建、测试并启动的模块化单体工程，为下一步中间件和业务实现提供稳定起点。

## 本次实现

创建根父工程与 app、account、fulfillment、pricing、payment 五个子模块。父 POM 管理版本、模块聚合与构建约束；app 依赖四个业务模块并提供唯一的启动类。四个业务模块没有 main 方法，也不独立占用端口。

Spring Boot 固定为 4.1.2，Maven 固定为 3.9.11，Wrapper 固定为 3.3.4，Java 编译目标为 21。Wrapper 还记录 Maven 分发文件的 SHA-256；第一次运行时自动下载并核验。构建同时检查 JDK 与 Maven 的版本范围。

配置分为 application.yml、application-dev.yml 和 application-test.yml。应用默认监听本机地址，使用 dev；测试启动真实的嵌入式 HTTP 服务并使用随机端口，避免与用户已有应用争抢 8080。

当前两项测试通过真实 HTTP 检查启动结果，不使用模拟对象，因此测试依赖排除了暂未使用的 Mockito。后续需要 Mock 时再按对应测试场景加入依赖和配置。

业务模块的 Module 类用于组件扫描定位。各模块预留 api、application、domain、infrastructure 分层，package-info.java 说明每层职责。业务实现会在后续任务加入这些包。

## 建议阅读顺序

| 顺序 | 文件 | 需要理解什么 |
|---|---|---|
| 1 | 根 pom.xml | parent 与 modules 的区别，依赖版本和构建约束 |
| 2 | dispatchnow-app/pom.xml | app 如何装配业务模块，为什么只有它打可执行包 |
| 3 | DispatchNowApplication.java | 单启动入口和组件扫描范围 |
| 4 | application.yml | 应用名、默认配置、端口和健康检查 |
| 5 | AccountModule.java 与 package-info.java | 业务模块边界与四层职责 |
| 6 | BootstrapHttpTest.java | 如何在真实 HTTP 服务上验证应用能够启动 |

## 执行与验收

在项目根目录执行 README 中的 `clean verify`，确认所有模块构建成功、两项 HTTP 测试通过。然后启动打包的 JAR，查询 /actuator/health 得到 UP。

| 验收项 | 通过标准 |
|---|---|
| 构建 | 父工程与五个子模块全部成功 |
| 自动化检查一 | 实际 HTTP 健康检查返回 200 和 UP，且不暴露健康详情 |
| 自动化检查二 | /actuator/env 返回 404，敏感管理端点未开放 |
| 打包启动 | app 可执行 JAR 能启动并通过健康检查 |
| 架构边界 | 只有一个启动类，业务模块没有启动插件 |

此时尚未接入数据库，不能据健康检查声称数据库、Redis 或 RabbitMQ 正常。业务接口、登录、订单和支付将在各自步骤实现。

## 下一步

第 02 步加入 MySQL、Redis、RabbitMQ 的 Compose 配置与连接配置，并验证真实依赖状态。Java 工程继续沿用当前模块结构。

## 官方参考

- [Spring Boot 环境要求](https://docs.spring.io/spring-boot/system-requirements.html)
- [Spring Boot 应用测试](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html)
- [Apache Maven Wrapper](https://maven.apache.org/tools/wrapper/)
