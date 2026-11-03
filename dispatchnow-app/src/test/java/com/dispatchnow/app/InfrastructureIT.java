package com.dispatchnow.app;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.UUID;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.env.Environment;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.core.io.ClassPathResource;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * opt-in 的真实连接验收：先启动依赖，再从根目录执行
 * ./mvnw -Pinfrastructure-it verify。连接已有虚拟机时增加
 * -Ddispatchnow.it.profile=vm。独立于不访问外部依赖的 BootstrapHttpTest。
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class InfrastructureIT {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private StringRedisTemplate redisTemplate;

    @Autowired
    private AmqpAdmin amqpAdmin;

    @Autowired
    private RabbitTemplate rabbitTemplate;

    @Autowired
    private Environment environment;

    private final JsonMapper jsonMapper = JsonMapper.builder().build();

    @Test
    void mysqlExecutesAQueryWithApplicationCredentials() {
        assertThat(jdbcTemplate.queryForObject("SELECT 1", Integer.class)).isEqualTo(1);
        assertThat(jdbcTemplate.queryForObject("SELECT DATABASE()", String.class))
                .isEqualTo(environment.getProperty("MYSQL_DATABASE", "project01"));
        assertThat(jdbcTemplate.queryForObject("SELECT @@session.time_zone", String.class))
                .isEqualTo("+00:00");
    }

    @Test
    void redisWritesReadsAndSetsTtlForAnIsolatedKey() {
        String key = "dispatchnow:verification:" + UUID.randomUUID();
        try {
            redisTemplate.opsForValue().set(key, "connected", Duration.ofSeconds(30));
            assertThat(redisTemplate.opsForValue().get(key)).isEqualTo("connected");
            assertThat(redisTemplate.getExpire(key)).isBetween(1L, 30L);
        } finally {
            redisTemplate.delete(key);
        }
    }

    @Test
    void databaseContainsTheApprovedApplicationTables() throws Exception {
        ClassPathResource resource = new ClassPathResource("database-required-tables.txt");
        List<String> expectedTables;
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                resource.getInputStream(), StandardCharsets.UTF_8))) {
            expectedTables = reader.lines()
                    .map(String::trim)
                    .filter(line -> !line.isEmpty() && !line.startsWith("#"))
                    .toList();
        }
        assertThat(expectedTables).hasSize(46).doesNotHaveDuplicates();
        List<String> actualTables = jdbcTemplate.queryForList(
                "SELECT table_name FROM information_schema.tables "
                        + "WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'",
                String.class);
        // 允许将来新增 flyway_schema_history 等表，不把表名存在等同于完整结构一致。
        assertThat(actualTables).containsAll(expectedTables);
    }

    @Test
    void rabbitRoutesAndReceivesAMessageOnATemporaryQueue() {
        String name = "dispatchnow.verification." + UUID.randomUUID();
        Queue queue = new Queue(name, false, false, true);
        String payload = "probe:" + UUID.randomUUID();
        try {
            amqpAdmin.declareQueue(queue);
            rabbitTemplate.convertAndSend("", name, payload);
            assertThat(rabbitTemplate.receiveAndConvert(name, 5000)).isEqualTo(payload);
        } finally {
            amqpAdmin.deleteQueue(name);
        }
    }

    @Test
    void healthReflectsAllThreeRealConnectionsWithoutExposingDetails() throws Exception {
        HttpResponse<String> response = get("/actuator/health/infrastructure");
        assertThat(response.statusCode()).isEqualTo(200);
        JsonNode body = jsonMapper.readTree(response.body());
        assertThat(body.path("status").asString()).isEqualTo("UP");
        for (String dependency : new String[]{"db", "redis", "rabbit"}) {
            JsonNode component = body.path("components").path(dependency);
            assertThat(component.path("status").asString()).isEqualTo("UP");
            assertThat(component.has("details")).isFalse();
        }
    }

    @Test
    void probesAndManagementBoundaryAreCorrect() throws Exception {
        assertThat(get("/actuator/health/readiness").statusCode()).isEqualTo(200);
        HttpResponse<String> liveness = get("/actuator/health/liveness");
        assertThat(liveness.statusCode()).isEqualTo(200);
        assertThat(jsonMapper.readTree(liveness.body()).has("components")).isFalse();
        assertThat(get("/actuator/env").statusCode()).isEqualTo(404);
        assertThat(jsonMapper.readTree(get("/actuator/health").body()).has("components")).isFalse();
    }

    private HttpResponse<String> get(String path) throws Exception {
        String port = environment.getRequiredProperty("local.server.port");
        HttpRequest request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path))
                .timeout(Duration.ofSeconds(15))
                .GET()
                .build();
        try (HttpClient client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(3))
                .build()) {
            return client.send(request, HttpResponse.BodyHandlers.ofString());
        }
    }
}
