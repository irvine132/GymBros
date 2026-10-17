package dev.gymbro;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
class LocalCors implements WebMvcConfigurer {
  @Override public void addCorsMappings(CorsRegistry registry) {
    // Local browser development only; never deploy with this policy unchanged.
    registry.addMapping("/api/v1/**")
      .allowedOriginPatterns("http://127.0.0.1:[*]", "http://localhost:[*]")
      .allowedMethods("GET", "POST", "PUT", "OPTIONS")
      .allowedHeaders("Authorization", "Content-Type");
  }
}
