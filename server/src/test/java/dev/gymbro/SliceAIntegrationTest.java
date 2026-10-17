package dev.gymbro;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.*;
import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SliceAIntegrationTest {
  @Autowired TestRestTemplate http;
  @Test void twoAccountsPrivateByDefaultAndBlock() {
    String suffix = UUID.randomUUID().toString().substring(0, 8);
    String a = register("alice" + suffix), b = register("bob" + suffix);
    assertThat(http.exchange("/api/v1/auth/register", HttpMethod.POST, request(Map.of("handle","alice" + suffix,"email","other" + suffix + "@example.test","password","local-demo-test-password"),null), String.class).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(http.exchange("/api/v1/auth/login", HttpMethod.POST, request(Map.of("email","alice" + suffix + "@example.test","password","incorrect-password"),null), String.class).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    String title = "Strength " + suffix;
    String sessionKey = UUID.randomUUID().toString();
    Map<String,Object> workout = Map.of("clientId", sessionKey, "title", title, "exercises", List.of(Map.of("name", "Squat", "sets", List.of(Map.of("reps", 5, "weight", 80, "unit", "kg")))));
    Map<?,?> created = post("/api/v1/sessions", workout, a, HttpStatus.CREATED);
    String id = created.get("id").toString();
    assertThat(post("/api/v1/sessions", workout, a, HttpStatus.OK).get("id")).isEqualTo(id);
    assertThat(get("/api/v1/sessions/" + id, b).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(http.exchange("/api/v1/sessions/" + id, HttpMethod.PUT, request(workout,b), String.class).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(http.exchange("/api/v1/sessions/" + id + "/complete", HttpMethod.POST, request(Map.of(),b), String.class).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(http.exchange("/api/v1/sessions", HttpMethod.POST, request(Map.of("clientId",UUID.randomUUID().toString(),"title","Invalid","exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",5,"weight",-1,"unit","kg"))))),a), String.class).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(feed(b)).doesNotContain(title);
    post("/api/v1/sessions/" + id + "/complete", Map.of(), a, HttpStatus.OK);
    post("/api/v1/sessions/" + id + "/complete", Map.of(), a, HttpStatus.OK);
    assertThat(feed(b)).doesNotContain(title);
    assertThat(http.exchange("/api/v1/sessions/" + id + "/posts", HttpMethod.POST, request(Map.of(), b), String.class).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    Map<?,?> post = post("/api/v1/sessions/" + id + "/posts", Map.of(), a, HttpStatus.CREATED);
    String postId = post.get("id").toString();
    assertThat(post("/api/v1/sessions/" + id + "/posts", Map.of(), a, HttpStatus.OK).get("id")).isEqualTo(postId);
    assertThat(feed(b)).contains(title).doesNotContain("startedAt", "email", "token");
    assertThat(get("/api/v1/posts/" + postId, b).getStatusCode()).isEqualTo(HttpStatus.OK);
    post("/api/v1/posts/" + postId + "/reports", Map.of("reason", "Review please"), b, HttpStatus.CREATED);
    post("/api/v1/posts/" + postId + "/reports", Map.of("reason", "Review please"), b, HttpStatus.OK);
    Map<?,?> me = get("/api/v1/me", a).getBody();
    post("/api/v1/users/" + me.get("id") + "/block", Map.of(), b, HttpStatus.CREATED);
    assertThat(get("/api/v1/posts/" + postId, b).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(http.exchange("/api/v1/posts/" + postId + "/reports",HttpMethod.POST,request(Map.of("reason","blocked"),b),String.class).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(feed(b)).doesNotContain(title);
    assertThat(get("/api/v1/posts/" + postId, a).getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(get("/api/v1/sessions/" + id, a).getStatusCode()).isEqualTo(HttpStatus.OK);
    http.exchange("/api/v1/auth/logout", HttpMethod.POST, request(Map.of(), a), String.class);
    assertThat(get("/api/v1/me", a).getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }
  private String register(String handle) {
    Map<?,?> result = post("/api/v1/auth/register", Map.of("handle",handle,"email",handle+"@example.test","password","local-demo-test-password"), null, HttpStatus.CREATED);
    String token = result.get("token").toString();
    assertThat(post("/api/v1/auth/login", Map.of("email",handle+"@example.test","password","local-demo-test-password"), null, HttpStatus.OK).get("token")).isNotNull();
    return token;
  }
  private HttpEntity<Object> request(Object body, String token) {
    HttpHeaders h = new HttpHeaders(); h.setContentType(MediaType.APPLICATION_JSON);
    if(token != null) h.setBearerAuth(token);
    return new HttpEntity<>(body,h);
  }
  @SuppressWarnings("unchecked") private Map<?,?> post(String path, Object body, String token, HttpStatus expected) {
    var res = http.exchange(path, HttpMethod.POST, request(body,token), Map.class);
    assertThat(res.getStatusCode()).as(path + ": " + res.getBody()).isEqualTo(expected);
    return res.getBody();
  }
  private ResponseEntity<Map> get(String path, String token) { return http.exchange(path,HttpMethod.GET,request(null,token),Map.class); }
  private String feed(String token) { return http.exchange("/api/v1/feed",HttpMethod.GET,request(null,token),String.class).getBody(); }
}
