package dev.gymbro;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import jakarta.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.*;
import java.util.regex.Pattern;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@SpringBootApplication
@RestController
@RequestMapping("/api/v1")
public class GymBroApplication {
  public static void main(String[] args) { SpringApplication.run(GymBroApplication.class, args); }
  private final JdbcTemplate db;
  private final ObjectMapper json;
  private final BCryptPasswordEncoder passwords = new BCryptPasswordEncoder(12);
  private final SecureRandom random = new SecureRandom();
  private static final Pattern HANDLE = Pattern.compile("[a-z0-9_]{3,32}");
  private static final Pattern EMAIL = Pattern.compile("[^\\s@]+@[^\\s@]+\\.[^\\s@]+");
  public GymBroApplication(JdbcTemplate db, ObjectMapper json) { this.db=db; this.json=json; }
  record Credentials(String email, String password) {}
  record Registration(String handle, String email, String password) {}
  record SetResult(Integer reps, BigDecimal weight, String unit) {}
  record Exercise(String name, List<SetResult> sets) {}
  record Workout(UUID clientId, String title, List<Exercise> exercises) {}
  record Report(String reason) {}
  private ResponseStatusException error(HttpStatus code) { return new ResponseStatusException(code); }
  private String digest(String token) {
    try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8))); }
    catch (Exception ex) { throw new IllegalStateException(ex); }
  }
  private UUID actor(HttpServletRequest request) {
    String bearer=request.getHeader("Authorization");
    if(bearer==null || !bearer.startsWith("Bearer ") || bearer.length()>512) throw error(HttpStatus.UNAUTHORIZED);
    List<UUID> found=db.query("SELECT user_id FROM auth_token WHERE digest=? AND revoked_at IS NULL AND expires_at>now()",(r,n)->(UUID)r.getObject(1),digest(bearer.substring(7)));
    if(found.isEmpty()) throw error(HttpStatus.UNAUTHORIZED);
    return found.getFirst();
  }
  private Map<String,Object> token(UUID user) {
    byte[] bytes=new byte[32]; random.nextBytes(bytes);
    String raw=Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    db.update("INSERT INTO auth_token(digest,user_id,expires_at) VALUES(?,?,now()+interval '7 days')", digest(raw),user);
    return Map.of("token",raw,"userId",user.toString());
  }
  @PostMapping("/auth/register") @Transactional
  public ResponseEntity<?> register(@RequestBody Registration in) {
    if(in==null || in.handle()==null || in.email()==null || in.password()==null) throw error(HttpStatus.BAD_REQUEST);
    String handle=in.handle().strip().toLowerCase(Locale.ROOT), email=in.email().strip().toLowerCase(Locale.ROOT);
    if(!HANDLE.matcher(handle).matches() || email.length()>254 || !EMAIL.matcher(email).matches() || in.password().length()<12 || in.password().length()>128) throw error(HttpStatus.BAD_REQUEST);
    UUID id=UUID.randomUUID();
    try { db.update("INSERT INTO app_user(id,handle,email,password_hash) VALUES(?,?,?,?)",id,handle,email,passwords.encode(in.password())); }
    catch(DataIntegrityViolationException ex) { throw error(HttpStatus.CONFLICT); }
    return ResponseEntity.status(HttpStatus.CREATED).body(token(id));
  }
  @PostMapping("/auth/login")
  public Map<String,Object> login(@RequestBody Credentials in) {
    if(in==null || in.email()==null || in.password()==null || in.email().length()>254 || in.password().length()>128) throw error(HttpStatus.BAD_REQUEST);
    List<Map<String,Object>> found=db.queryForList("SELECT id,password_hash FROM app_user WHERE email=?",in.email().strip().toLowerCase(Locale.ROOT));
    if(found.isEmpty() || !passwords.matches(in.password(),(String)found.getFirst().get("password_hash"))) throw error(HttpStatus.UNAUTHORIZED);
    return token((UUID)found.getFirst().get("id"));
  }
  @PostMapping("/auth/logout") public ResponseEntity<Void> logout(HttpServletRequest request) {
    actor(request); db.update("UPDATE auth_token SET revoked_at=now() WHERE digest=?",digest(request.getHeader("Authorization").substring(7)));
    return ResponseEntity.noContent().build();
  }
  @GetMapping("/me") public Map<String,Object> me(HttpServletRequest request) {
    return db.queryForMap("SELECT id,handle FROM app_user WHERE id=?",actor(request));
  }
  @GetMapping("/me/summary") public Map<String,Object> mySummary(HttpServletRequest request) {
    UUID owner=actor(request);
    return Map.of("handle",db.queryForObject("SELECT handle FROM app_user WHERE id=?",String.class,owner),
      "sessions",db.queryForObject("SELECT count(*) FROM workout_session WHERE owner_id=? AND status='COMPLETED'",Integer.class,owner),
      "publications",db.queryForObject("SELECT count(*) FROM activity_post WHERE author_id=? AND deleted_at IS NULL",Integer.class,owner));
  }
  // Versioned-in-source starter catalogue: the saved workout contains its own name snapshot.
  @GetMapping("/exercises") public List<Map<String,String>> exercises(HttpServletRequest request) {
    actor(request);
    return List.of(
      Map.of("name","Squat","category","Jambes","unit","kg"),
      Map.of("name","Soulevé de terre","category","Jambes","unit","kg"),
      Map.of("name","Développé couché","category","Haut du corps","unit","kg"),
      Map.of("name","Développé épaules","category","Haut du corps","unit","kg"),
      Map.of("name","Rowing barre","category","Dos","unit","kg"),
      Map.of("name","Tractions","category","Dos","unit","kg"),
      Map.of("name","Fentes","category","Jambes","unit","kg"),
      Map.of("name","Curl biceps","category","Bras","unit","kg"));
  }
  private void validate(Workout in) {
    if(in==null || in.clientId()==null || in.title()==null || in.title().isBlank() || in.title().length()>100 || in.exercises()==null || in.exercises().isEmpty() || in.exercises().size()>20) throw error(HttpStatus.BAD_REQUEST);
    for(Exercise exercise:in.exercises()) {
      if(exercise==null || exercise.name()==null || exercise.name().isBlank() || exercise.name().length()>80 || exercise.sets()==null || exercise.sets().isEmpty() || exercise.sets().size()>30) throw error(HttpStatus.BAD_REQUEST);
      for(SetResult set:exercise.sets()) {
        if(set==null || set.reps()==null || set.reps()<1 || set.reps()>1000 || set.weight()==null || set.weight().scale()>2 || set.weight().signum()<0 || set.weight().compareTo(new BigDecimal("10000"))>0 || !List.of("kg","lb").contains(set.unit())) throw error(HttpStatus.BAD_REQUEST);
      }
    }
  }
  private String encode(Workout in) {
    try { return json.writeValueAsString(in); } catch(Exception ex) { throw error(HttpStatus.BAD_REQUEST); }
  }
  private Map<String,Object> session(UUID id, UUID owner) {
    List<Map<String,Object>> found=db.queryForList("SELECT s.id,s.client_id,s.title,s.payload::text AS payload,s.status,s.started_at,s.completed_at,s.result_schema_version,EXISTS(SELECT 1 FROM activity_post p WHERE p.session_id=s.id AND p.deleted_at IS NULL) AS published FROM workout_session s WHERE s.id=? AND s.owner_id=?",id,owner);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    Map<String,Object> row=found.getFirst();
    try { return Map.of("id",row.get("id"),"clientId",row.get("client_id"),"title",row.get("title"),"workout",json.readTree((String)row.get("payload")),"status",row.get("status"),"startedAt",row.get("started_at").toString(),"published",row.get("published"),"resultSchemaVersion",row.get("result_schema_version")); }
    catch(Exception ex) { throw new IllegalStateException(ex); }
  }
  @PostMapping("/sessions") @Transactional
  public ResponseEntity<?> create(@RequestBody Workout in,HttpServletRequest request) {
    UUID owner=actor(request); validate(in);
    UUID id=UUID.randomUUID();
    int inserted=db.update("INSERT INTO workout_session(id,owner_id,client_id,title,payload) VALUES(?,?,?,?,?::jsonb) ON CONFLICT(owner_id,client_id) DO NOTHING",id,owner,in.clientId(),in.title(),encode(in));
    if(inserted==0) id=db.queryForObject("SELECT id FROM workout_session WHERE owner_id=? AND client_id=?",UUID.class,owner,in.clientId());
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(session(id,owner));
  }
  @PutMapping("/sessions/{id}")
  public Map<String,Object> update(@PathVariable UUID id,@RequestBody Workout in,HttpServletRequest request) {
    UUID owner=actor(request); validate(in);
    int count=db.update("UPDATE workout_session SET title=?,payload=?::jsonb WHERE id=? AND owner_id=? AND client_id=? AND status='DRAFT'",in.title(),encode(in),id,owner,in.clientId());
    if(count==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  @GetMapping("/sessions/{id}") public Map<String,Object> one(@PathVariable UUID id,HttpServletRequest request) { return session(id,actor(request)); }
  @GetMapping("/sessions") public List<Map<String,Object>> mine(HttpServletRequest request) {
    UUID owner=actor(request);
    return db.queryForList("SELECT id,title,status,started_at,completed_at FROM workout_session WHERE owner_id=? ORDER BY started_at DESC LIMIT 50",owner);
  }
  @PostMapping("/sessions/{id}/complete")
  public Map<String,Object> complete(@PathVariable UUID id,HttpServletRequest request) {
    UUID owner=actor(request);
    int changed=db.update("UPDATE workout_session SET status='COMPLETED',completed_at=now() WHERE id=? AND owner_id=? AND status='DRAFT'",id,owner);
    if(changed==0 && db.queryForObject("SELECT count(*) FROM workout_session WHERE id=? AND owner_id=?",Integer.class,id,owner)==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  @PostMapping("/sessions/{id}/posts") @Transactional
  public ResponseEntity<?> publish(@PathVariable UUID id,HttpServletRequest request) {
    UUID owner=actor(request); UUID postId=UUID.randomUUID();
    int inserted=db.update("INSERT INTO activity_post(id,author_id,session_id,title) SELECT ?,owner_id,id,title FROM workout_session WHERE id=? AND owner_id=? AND status='COMPLETED' ON CONFLICT(session_id) DO NOTHING",postId,id,owner);
    List<UUID> found=db.query("SELECT id FROM activity_post WHERE session_id=? AND author_id=?",(r,n)->(UUID)r.getObject(1),id,owner);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(post(found.getFirst(),owner));
  }
  private static final String VISIBLE="p.deleted_at IS NULL AND p.audience='PUBLIC' AND NOT EXISTS (SELECT 1 FROM user_block b WHERE (b.blocker_id=? AND b.blocked_id=p.author_id) OR (b.blocked_id=? AND b.blocker_id=p.author_id))";
  private List<Map<String,Object>> publicExercises(String payload) {
    try {
      JsonNode nodes=json.readTree(payload).path("exercises");
      List<Map<String,Object>> result=new ArrayList<>();
      if(!nodes.isArray()) return result;
      for(JsonNode exercise:nodes) {
        List<Map<String,Object>> sets=new ArrayList<>();
        for(JsonNode set:exercise.path("sets")) {
          sets.add(Map.of("reps",set.path("reps").asInt(),"weight",set.path("weight").decimalValue(),"unit",set.path("unit").asText()));
        }
        result.add(Map.of("name",exercise.path("name").asText(),"sets",sets));
      }
      return result;
    } catch(Exception ex) { throw new IllegalStateException("Invalid stored workout payload",ex); }
  }
  private Map<String,Object> publicRow(Map<String,Object> row) {
    return Map.of("id",row.get("id"),"authorId",row.get("author_id"),"author",row.get("handle"),"title",row.get("title"),"sport","STRENGTH","exerciseCount",row.get("exercise_count"),"date",row.get("day").toString(),"exercises",publicExercises((String)row.get("payload")));
  }
  private static final String SELECT="SELECT p.id,p.author_id,u.handle,p.title,(p.published_at AT TIME ZONE 'UTC')::date AS day,jsonb_array_length(s.payload->'exercises') AS exercise_count,s.payload::text AS payload FROM activity_post p JOIN app_user u ON u.id=p.author_id JOIN workout_session s ON s.id=p.session_id WHERE ";
  private Map<String,Object> post(UUID id,UUID actor) {
    List<Map<String,Object>> found=db.queryForList(SELECT+VISIBLE+" AND p.id=?",actor,actor,id);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return publicRow(found.getFirst());
  }
  @GetMapping("/posts/{id}") public Map<String,Object> detail(@PathVariable UUID id,HttpServletRequest request) { return post(id,actor(request)); }
  @GetMapping("/feed") public List<Map<String,Object>> feed(HttpServletRequest request,@RequestParam(defaultValue="0") int offset) {
    UUID user=actor(request); if(offset<0 || offset>1000) throw error(HttpStatus.BAD_REQUEST);
    return db.queryForList(SELECT+VISIBLE+" ORDER BY p.published_at DESC,p.id DESC LIMIT 20 OFFSET ?",user,user,offset).stream().map(this::publicRow).toList();
  }
  @PostMapping("/users/{id}/block") public ResponseEntity<?> block(@PathVariable UUID id,HttpServletRequest request) {
    UUID actor=actor(request); if(id.equals(actor)) throw error(HttpStatus.BAD_REQUEST);
    int inserted=db.update("INSERT INTO user_block(blocker_id,blocked_id) SELECT ?,id FROM app_user WHERE id=? ON CONFLICT DO NOTHING",actor,id);
    if(inserted==0 && db.queryForObject("SELECT count(*) FROM app_user WHERE id=?",Integer.class,id)==0) throw error(HttpStatus.NOT_FOUND);
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(Map.of("blocked",true));
  }
  @PostMapping("/posts/{id}/reports") public ResponseEntity<?> report(@PathVariable UUID id,@RequestBody Report in,HttpServletRequest request) {
    UUID actor=actor(request); post(id,actor);
    if(in==null || in.reason()==null || in.reason().isBlank() || in.reason().length()>300) throw error(HttpStatus.BAD_REQUEST);
    UUID reportId=UUID.randomUUID();
    int inserted=db.update("INSERT INTO post_report(id,reporter_id,post_id,reason) VALUES(?,?,?,?) ON CONFLICT(reporter_id,post_id) DO NOTHING",reportId,actor,id,in.reason());
    if(inserted==0) reportId=db.queryForObject("SELECT id FROM post_report WHERE reporter_id=? AND post_id=?",UUID.class,actor,id);
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(Map.of("id",reportId));
  }
}
