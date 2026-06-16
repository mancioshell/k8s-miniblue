# ---- build stage: compile + package inside the image (no local Java/Maven needed) ----
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /workspace

# Cache dependencies first.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---- runtime stage: minimal JRE, non-root, no secrets baked in ----
FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app

# Links the published GHCR package to the repo (shows under the repo's "Packages" tab).
LABEL org.opencontainers.image.source=https://github.com/mancioshell/k8s-miniblue

# Non-root user.
RUN useradd -r -u 10001 appuser
USER appuser

COPY --from=build /workspace/target/app.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
