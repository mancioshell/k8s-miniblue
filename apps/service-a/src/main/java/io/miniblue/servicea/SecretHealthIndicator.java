package io.miniblue.servicea;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Marks the pod NOT ready when the runtime-injected secret is absent, so a missing Key Vault
 * secret keeps the pod out of service (SecretProviderClass behavioral contract #4).
 */
@Component("secret")
public class SecretHealthIndicator implements HealthIndicator {

    @Value("${APP_GREETING_SECRET:}")
    private String greetingSecret;

    @Override
    public Health health() {
        if (greetingSecret == null || greetingSecret.isBlank()) {
            return Health.down().withDetail("APP_GREETING_SECRET", "absent").build();
        }
        return Health.up().withDetail("APP_GREETING_SECRET", "present").build();
    }
}
