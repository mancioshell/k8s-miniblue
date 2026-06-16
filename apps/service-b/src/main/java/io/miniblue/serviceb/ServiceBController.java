package io.miniblue.serviceb;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Exposes a farewell built from a secret-backed environment variable. The secret value is
 * injected at runtime from Key Vault via the Secrets Store CSI driver (never baked into the
 * image or chart) — same contract as service-a (FR-011/FR-012).
 */
@RestController
public class ServiceBController {

    // Populated from the synced Kubernetes Secret (CSI). Empty default makes absence observable.
    @Value("${APP_GREETING_SECRET:}")
    private String greetingSecret;

    @Value("${app.version:unknown}")
    private String appVersion;

    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
            "app", "service-b",
            "version", appVersion
        );
    }

    @GetMapping("/greeting")
    public Map<String, Object> greeting() {
        boolean secretPresent = greetingSecret != null && !greetingSecret.isBlank();
        return Map.of(
            "message", secretPresent ? greetingSecret : "<no secret injected>",
            "secretPresent", secretPresent,
            "version", appVersion
        );
    }
}
