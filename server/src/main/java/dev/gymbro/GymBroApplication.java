package dev.gymbro;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.servlet.http.HttpServletRequest;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.sql.Timestamp;
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
  record WodResult(Integer rounds, Integer reps, Integer timeSeconds, Boolean scaled) {}
  record Wod(UUID clientId, String title, String format, Integer timeCapSeconds, List<String> movements, WodResult result) {}
  record HyroxSegment(String type, String name, Integer distanceMeters, Integer durationSeconds,
                      Integer reps, BigDecimal weight, String unit) {}
  record Hyrox(UUID clientId, String title, List<HyroxSegment> segments, Integer totalSeconds, String notes) {}
  record Report(String reason) {}
  record ProfileUpdate(String displayName, @JsonProperty("private") Boolean privateAccount, String unit) {}
  record Publication(String audience) {}
  record TemplateDefinition(String title, List<Exercise> exercises) {}
  record StartTemplate(UUID clientId) {}
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
    if(found.isEmpty() || found.getFirst().get("password_hash")==null || !passwords.matches(in.password(),(String)found.getFirst().get("password_hash"))) throw error(HttpStatus.UNAUTHORIZED);
    return token((UUID)found.getFirst().get("id"));
  }
  @PostMapping("/auth/logout") public ResponseEntity<Void> logout(HttpServletRequest request) {
    actor(request); db.update("UPDATE auth_token SET revoked_at=now() WHERE digest=?",digest(request.getHeader("Authorization").substring(7)));
    return ResponseEntity.noContent().build();
  }
  @GetMapping("/me") public Map<String,Object> me(HttpServletRequest request) {
    return db.queryForMap("SELECT id,handle,display_name AS \"displayName\",is_private AS \"private\",preferred_unit AS unit FROM app_user WHERE id=?",actor(request));
  }
  @PutMapping("/me/profile") @Transactional public Map<String,Object> updateProfile(@RequestBody ProfileUpdate in,HttpServletRequest request) {
    UUID owner=actor(request);
    if(in==null || in.privateAccount()==null || !List.of("kg","lb").contains(in.unit()) ||
      (in.displayName()!=null && (in.displayName().strip().length()>60 || in.displayName().strip().isEmpty()))) throw error(HttpStatus.BAD_REQUEST);
    db.update("UPDATE app_user SET display_name=?,is_private=?,preferred_unit=? WHERE id=?",in.displayName()==null?null:in.displayName().strip(),in.privateAccount(),in.unit(),owner);
    return me(request);
  }
  private static final String NO_BLOCK="NOT EXISTS (SELECT 1 FROM user_block b WHERE (b.blocker_id=? AND b.blocked_id=u.id) OR (b.blocked_id=? AND b.blocker_id=u.id))";
  private Map<String,Object> profileRow(Map<String,Object> row) {
    Map<String,Object> out=new LinkedHashMap<>();
    out.put("id",row.get("id")); out.put("handle",row.get("handle"));
    out.put("displayName",row.get("displayName")); out.put("private",row.get("private"));
    out.put("relation",row.get("relation"));
    return out;
  }
  private static final String PROFILE="SELECT u.id,u.handle,u.display_name AS \"displayName\",u.is_private AS \"private\",COALESCE(f.status,'NONE') AS relation FROM app_user u LEFT JOIN user_follow f ON f.followed_id=u.id AND f.follower_id=? WHERE ";
  @GetMapping("/users") public List<Map<String,Object>> search(@RequestParam String query,HttpServletRequest request) {
    UUID viewer=actor(request);
    if(query==null || query.strip().length()<2 || query.strip().length()>60) throw error(HttpStatus.BAD_REQUEST);
    String term="%"+query.strip().replace("\\","\\\\").replace("%","\\%").replace("_","\\_")+"%";
    return db.queryForList(PROFILE+"u.id<>? AND "+NO_BLOCK+" AND (u.handle ILIKE ? ESCAPE '\\' OR u.display_name ILIKE ? ESCAPE '\\') ORDER BY u.handle LIMIT 20",viewer,viewer,viewer,viewer,term,term).stream().map(this::profileRow).toList();
  }
  @GetMapping("/users/{id}") public Map<String,Object> profile(@PathVariable UUID id,HttpServletRequest request) {
    UUID viewer=actor(request);
    List<Map<String,Object>> found=db.queryForList(PROFILE+"u.id=? AND (u.id=? OR "+NO_BLOCK+")",viewer,id,viewer,viewer,viewer);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return profileRow(found.getFirst());
  }
  private void available(UUID viewer,UUID target) {
    if(viewer.equals(target)) throw error(HttpStatus.BAD_REQUEST);
    if(db.queryForObject("SELECT count(*) FROM app_user u WHERE u.id=? AND "+NO_BLOCK,Integer.class,target,viewer,viewer)==0) throw error(HttpStatus.NOT_FOUND);
  }
  @PostMapping("/users/{id}/follow") @Transactional
  public ResponseEntity<?> follow(@PathVariable UUID id,HttpServletRequest request) {
    UUID viewer=actor(request); available(viewer,id);
    String status=db.queryForObject("SELECT CASE WHEN is_private THEN 'PENDING' ELSE 'ACCEPTED' END FROM app_user WHERE id=? FOR UPDATE",String.class,id);
    db.update("INSERT INTO user_follow(follower_id,followed_id,status) VALUES(?,?,?) ON CONFLICT(follower_id,followed_id) DO UPDATE SET status='ACCEPTED' WHERE EXCLUDED.status='ACCEPTED'",viewer,id,status);
    String current=db.queryForObject("SELECT status FROM user_follow WHERE follower_id=? AND followed_id=?",String.class,viewer,id);
    return ResponseEntity.status(current.equals("PENDING")?HttpStatus.ACCEPTED:HttpStatus.OK).body(Map.of("status",current));
  }
  @DeleteMapping("/users/{id}/follow") public Map<String,Object> unfollow(@PathVariable UUID id,HttpServletRequest request) {
    UUID viewer=actor(request); available(viewer,id);
    db.update("DELETE FROM user_follow WHERE follower_id=? AND followed_id=?",viewer,id);
    return Map.of("status","NONE");
  }
  @GetMapping("/me/follow-requests") public List<Map<String,Object>> requests(HttpServletRequest request) {
    UUID owner=actor(request);
    return db.queryForList("SELECT u.id,u.handle FROM user_follow f JOIN app_user u ON u.id=f.follower_id WHERE f.followed_id=? AND f.status='PENDING' AND NOT EXISTS (SELECT 1 FROM user_block b WHERE (b.blocker_id=? AND b.blocked_id=u.id) OR (b.blocked_id=? AND b.blocker_id=u.id)) ORDER BY u.handle LIMIT 100",owner,owner,owner);
  }
  private Map<String,Object> decide(UUID requester,HttpServletRequest request,boolean accept) {
    UUID owner=actor(request); available(owner,requester);
    int changed=accept?db.update("UPDATE user_follow SET status='ACCEPTED' WHERE follower_id=? AND followed_id=? AND status='PENDING'",requester,owner)
      :db.update("DELETE FROM user_follow WHERE follower_id=? AND followed_id=? AND status='PENDING'",requester,owner);
    if(changed==0) throw error(HttpStatus.NOT_FOUND);
    return Map.of("status",accept?"ACCEPTED":"NONE");
  }
  @PostMapping("/follow-requests/{id}/accept") public Map<String,Object> accept(@PathVariable UUID id,HttpServletRequest request) { return decide(id,request,true); }
  @PostMapping("/follow-requests/{id}/reject") public Map<String,Object> reject(@PathVariable UUID id,HttpServletRequest request) { return decide(id,request,false); }
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
  private void validateWod(Wod in) {
    if(in==null || in.clientId()==null || in.title()==null || in.title().isBlank() || in.title().length()>100 ||
      !List.of("AMRAP","EMOM","FOR_TIME").contains(in.format()==null?"":in.format()) ||
      in.timeCapSeconds()==null || in.timeCapSeconds()<60 || in.timeCapSeconds()>7200 ||
      in.movements()==null || in.movements().isEmpty() || in.movements().size()>20 ||
      in.movements().stream().anyMatch(m->m==null || m.isBlank() || m.length()>80) || in.result()==null ||
      in.result().scaled()==null) throw error(HttpStatus.BAD_REQUEST);
    WodResult r=in.result();
    if(in.format().equals("FOR_TIME") ?
      r.timeSeconds()==null || r.timeSeconds()<1 || r.timeSeconds()>in.timeCapSeconds() || r.rounds()!=null || r.reps()!=null :
      r.timeSeconds()!=null || r.rounds()==null || r.rounds()<0 || r.rounds()>1000 || r.reps()==null ||
        r.reps()<0 || r.reps()>1000 || (r.rounds()==0 && r.reps()==0)) throw error(HttpStatus.BAD_REQUEST);
  }
  @PostMapping("/wods") @Transactional
  public ResponseEntity<?> createWod(@RequestBody Wod in,HttpServletRequest request) {
    UUID owner=actor(request); validateWod(in);
    UUID id=UUID.randomUUID();
    String payload;
    try { payload=json.writeValueAsString(in); } catch(Exception ex) { throw error(HttpStatus.BAD_REQUEST); }
    int inserted=db.update("INSERT INTO workout_session(id,owner_id,client_id,title,payload,result_schema_version) VALUES(?,?,?,?,?::jsonb,2) ON CONFLICT(owner_id,client_id) DO NOTHING",id,owner,in.clientId(),in.title().strip(),payload);
    if(inserted==0) {
      List<UUID> existing=db.query("SELECT id FROM workout_session WHERE owner_id=? AND client_id=? AND result_schema_version=2",(r,n)->(UUID)r.getObject(1),owner,in.clientId());
      if(existing.isEmpty()) throw error(HttpStatus.CONFLICT);
      id=existing.getFirst();
    }
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(session(id,owner));
  }
  @PutMapping("/wods/{id}")
  public Map<String,Object> updateWod(@PathVariable UUID id,@RequestBody Wod in,HttpServletRequest request) {
    UUID owner=actor(request); validateWod(in);
    String payload;
    try { payload=json.writeValueAsString(in); } catch(Exception ex) { throw error(HttpStatus.BAD_REQUEST); }
    if(db.update("UPDATE workout_session SET title=?,payload=?::jsonb WHERE id=? AND owner_id=? AND client_id=? AND result_schema_version=2 AND status='DRAFT'",in.title().strip(),payload,id,owner,in.clientId())==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  private void validateHyrox(Hyrox in) {
    if(in==null || in.clientId()==null || in.title()==null || in.title().isBlank() || in.title().length()>100 ||
      in.totalSeconds()==null || in.totalSeconds()<1 || in.totalSeconds()>86400 ||
      in.notes()!=null && in.notes().length()>1000 || in.segments()==null ||
      in.segments().size()<2 || in.segments().size()>20) throw error(HttpStatus.BAD_REQUEST);
    int sum=0; boolean run=false, station=false;
    for(HyroxSegment segment:in.segments()) {
      if(segment==null || segment.durationSeconds()==null || segment.durationSeconds()<1 || segment.durationSeconds()>86400)
        throw error(HttpStatus.BAD_REQUEST);
      sum+=segment.durationSeconds();
      if("RUN".equals(segment.type())) {
        run=true;
        if(segment.distanceMeters()==null || segment.distanceMeters()<1 || segment.distanceMeters()>50000 ||
          segment.name()!=null || segment.reps()!=null || segment.weight()!=null || segment.unit()!=null) throw error(HttpStatus.BAD_REQUEST);
      } else if("STATION".equals(segment.type())) {
        station=true;
        if(segment.name()==null || segment.name().isBlank() || segment.name().length()>80 || segment.distanceMeters()!=null ||
          segment.reps()!=null && (segment.reps()<1 || segment.reps()>10000) ||
          segment.weight()!=null && (segment.weight().signum()<0 || segment.weight().scale()>2 || segment.weight().compareTo(new BigDecimal("10000"))>0) ||
          (segment.weight()==null) != (segment.unit()==null) ||
          segment.unit()!=null && !List.of("kg","lb").contains(segment.unit())) throw error(HttpStatus.BAD_REQUEST);
      } else throw error(HttpStatus.BAD_REQUEST);
    }
    if(!run || !station || sum>in.totalSeconds()) throw error(HttpStatus.BAD_REQUEST);
  }
  @PostMapping("/hyrox") @Transactional
  public ResponseEntity<?> createHyrox(@RequestBody Hyrox in,HttpServletRequest request) {
    UUID owner=actor(request); validateHyrox(in);
    UUID id=UUID.randomUUID();
    int inserted=db.update("INSERT INTO workout_session(id,owner_id,client_id,title,payload,result_schema_version) VALUES(?,?,?,?,?::jsonb,3) ON CONFLICT(owner_id,client_id) DO NOTHING",
      id,owner,in.clientId(),in.title().strip(),encodeHyrox(in));
    if(inserted==0) {
      List<UUID> existing=db.query("SELECT id FROM workout_session WHERE owner_id=? AND client_id=? AND result_schema_version=3",(r,n)->(UUID)r.getObject(1),owner,in.clientId());
      if(existing.isEmpty()) throw error(HttpStatus.CONFLICT);
      id=existing.getFirst();
    }
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(session(id,owner));
  }
  private String encodeHyrox(Hyrox in) {
    try { return json.writeValueAsString(in); } catch(Exception ex) { throw error(HttpStatus.BAD_REQUEST); }
  }
  @PutMapping("/hyrox/{id}")
  public Map<String,Object> updateHyrox(@PathVariable UUID id,@RequestBody Hyrox in,HttpServletRequest request) {
    UUID owner=actor(request); validateHyrox(in);
    if(db.update("UPDATE workout_session SET title=?,payload=?::jsonb WHERE id=? AND owner_id=? AND client_id=? AND result_schema_version=3 AND status='DRAFT'",
      in.title().strip(),encodeHyrox(in),id,owner,in.clientId())==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  private Map<String,Object> session(UUID id, UUID owner) {
    List<Map<String,Object>> found=db.queryForList("SELECT s.id,s.client_id,s.title,s.payload::text AS payload,s.status,s.started_at,s.completed_at,s.result_schema_version,s.source_post_id,EXISTS(SELECT 1 FROM activity_post p WHERE p.session_id=s.id AND p.deleted_at IS NULL) AS published FROM workout_session s WHERE s.id=? AND s.owner_id=?",id,owner);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    Map<String,Object> row=found.getFirst();
    try {
      Map<String,Object> out=new LinkedHashMap<>(Map.of("id",row.get("id"),"clientId",row.get("client_id"),"title",row.get("title"),"workout",json.readTree((String)row.get("payload")),"status",row.get("status"),"startedAt",row.get("started_at").toString(),"published",row.get("published"),"resultSchemaVersion",row.get("result_schema_version")));
      provenance(out,(UUID)row.get("source_post_id"),owner);
      return out;
    }
    catch(Exception ex) { throw new IllegalStateException(ex); }
  }
  @PostMapping("/sessions") @Transactional
  public ResponseEntity<?> create(@RequestBody Workout in,HttpServletRequest request) {
    UUID owner=actor(request); validate(in);
    UUID id=UUID.randomUUID();
    int inserted=db.update("INSERT INTO workout_session(id,owner_id,client_id,title,payload) VALUES(?,?,?,?,?::jsonb) ON CONFLICT(owner_id,client_id) DO NOTHING",id,owner,in.clientId(),in.title(),encode(in));
    if(inserted==0) {
      List<UUID> existing=db.query("SELECT id FROM workout_session WHERE owner_id=? AND client_id=? AND result_schema_version=1",(r,n)->(UUID)r.getObject(1),owner,in.clientId());
      if(existing.isEmpty()) throw error(HttpStatus.CONFLICT);
      id=existing.getFirst();
    }
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(session(id,owner));
  }
  @PutMapping("/sessions/{id}")
  public Map<String,Object> update(@PathVariable UUID id,@RequestBody Workout in,HttpServletRequest request) {
    UUID owner=actor(request); validate(in);
    int count=db.update("UPDATE workout_session SET title=?,payload=?::jsonb WHERE id=? AND owner_id=? AND client_id=? AND status='DRAFT' AND result_schema_version=1",in.title(),encode(in),id,owner,in.clientId());
    if(count==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  @GetMapping("/sessions/{id}") public Map<String,Object> one(@PathVariable UUID id,HttpServletRequest request) { return session(id,actor(request)); }
  @GetMapping("/sessions") public List<Map<String,Object>> mine(HttpServletRequest request) {
    UUID owner=actor(request);
    return db.queryForList("SELECT s.id,s.title,s.status,s.started_at,s.completed_at,EXISTS(SELECT 1 FROM activity_post p WHERE p.session_id=s.id AND p.deleted_at IS NULL) AS published FROM workout_session s WHERE s.owner_id=? ORDER BY s.started_at DESC LIMIT 50",owner);
  }
  @PostMapping("/sessions/{id}/complete")
  public Map<String,Object> complete(@PathVariable UUID id,HttpServletRequest request) {
    UUID owner=actor(request);
    int changed=db.update("UPDATE workout_session SET status='COMPLETED',completed_at=now() WHERE id=? AND owner_id=? AND status='DRAFT'",id,owner);
    if(changed==0 && db.queryForObject("SELECT count(*) FROM workout_session WHERE id=? AND owner_id=?",Integer.class,id,owner)==0) throw error(HttpStatus.NOT_FOUND);
    return session(id,owner);
  }
  // Conditional offline completion never commits a different device's draft.
  @PostMapping("/sessions/{id}/complete-expected") @Transactional
  public Map<String,Object> completeExpected(@PathVariable UUID id,@RequestBody com.fasterxml.jackson.databind.JsonNode expected,HttpServletRequest request) {
    UUID owner=actor(request);
    if(expected==null || !expected.isObject()) throw error(HttpStatus.BAD_REQUEST);
    int changed=db.update("UPDATE workout_session SET status='COMPLETED',completed_at=now() WHERE id=? AND owner_id=? AND status='DRAFT' AND jsonb_strip_nulls(payload)=jsonb_strip_nulls(?::jsonb)",
      id,owner,expected.toString());
    if(changed==0) {
      List<Map<String,Object>> rows=db.queryForList("SELECT status,jsonb_strip_nulls(payload)=jsonb_strip_nulls(?::jsonb) AS matches FROM workout_session WHERE id=? AND owner_id=?",expected.toString(),id,owner);
      if(rows.isEmpty()) throw error(HttpStatus.NOT_FOUND);
      if(!"COMPLETED".equals(rows.getFirst().get("status")) || !Boolean.TRUE.equals(rows.getFirst().get("matches"))) throw error(HttpStatus.CONFLICT);
    }
    return session(id,owner);
  }
  @PostMapping("/sessions/{id}/posts") @Transactional
  public ResponseEntity<?> publish(@PathVariable UUID id,@RequestBody(required=false) Publication in,HttpServletRequest request) {
    String audience=in==null || in.audience()==null?"PUBLIC":in.audience();
    if(!List.of("PUBLIC","FOLLOWERS").contains(audience)) throw error(HttpStatus.BAD_REQUEST);
    UUID owner=actor(request); UUID postId=UUID.randomUUID();
    int inserted=db.update("INSERT INTO activity_post(id,author_id,session_id,title,audience) SELECT ?,owner_id,id,title,? FROM workout_session WHERE id=? AND owner_id=? AND status='COMPLETED' ON CONFLICT(session_id) DO NOTHING",postId,audience,id,owner);
    List<UUID> found=db.query("SELECT id FROM activity_post WHERE session_id=? AND author_id=?",(r,n)->(UUID)r.getObject(1),id,owner);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(post(found.getFirst(),owner));
  }
  private static final String VISIBLE="p.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM user_block b WHERE (b.blocker_id=? AND b.blocked_id=p.author_id) OR (b.blocked_id=? AND b.blocker_id=p.author_id))";
  private static final String ACCEPTED="EXISTS (SELECT 1 FROM user_follow f WHERE f.follower_id=? AND f.followed_id=p.author_id AND f.status='ACCEPTED')";
  private static final String DISCOVER=VISIBLE+" AND p.audience='PUBLIC' AND NOT u.is_private";
  private static final String DETAIL=VISIBLE+" AND (p.author_id=? OR ("+ACCEPTED+" AND p.audience IN ('PUBLIC','FOLLOWERS')) OR (NOT u.is_private AND p.audience='PUBLIC'))";
  // A source ID and identity must never leave the API without a fresh detail permission check.
  private void provenance(Map<String,Object> out,UUID source,UUID viewer) {
    if(source==null) return;
    List<Map<String,Object>> visible=db.queryForList("SELECT p.id,u.handle FROM activity_post p JOIN app_user u ON u.id=p.author_id WHERE "+DETAIL+" AND p.id=?",viewer,viewer,viewer,viewer,source);
    if(visible.isEmpty()) out.put("sourceUnavailable",true);
    else {
      out.put("sourcePostId",visible.getFirst().get("id"));
      out.put("sourceAuthor",visible.getFirst().get("handle"));
    }
  }
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
  private Map<String,Object> publicRow(Map<String,Object> row,UUID viewer) {
    int version=((Number)row.get("result_schema_version")).intValue();
    Map<String,Object> out=new LinkedHashMap<>(Map.of("id",row.get("id"),"authorId",row.get("author_id"),"author",row.get("handle"),"title",row.get("title"),"sport",version==3?"HYROX":version==2?"CROSSFIT":"STRENGTH","date",row.get("day").toString()));
    if(version==3) {
      try {
        JsonNode payload=json.readTree((String)row.get("payload"));
        out.put("totalSeconds",payload.path("totalSeconds").asInt());
        List<Map<String,Object>> segments=new ArrayList<>();
        for(JsonNode item:payload.path("segments")) {
          Map<String,Object> projected=new LinkedHashMap<>();
          for(String key:List.of("type","name","distanceMeters","durationSeconds","reps","weight","unit"))
            if(item.hasNonNull(key)) projected.put(key,json.convertValue(item.get(key),Object.class));
          segments.add(projected);
        }
        out.put("segments",segments);
      } catch(Exception ex) { throw new IllegalStateException("Invalid stored Hyrox",ex); }
    } else if(version==2) {
      try {
        JsonNode payload=json.readTree((String)row.get("payload"));
        out.put("format",payload.path("format").asText());
        out.put("timeCapSeconds",payload.path("timeCapSeconds").asInt());
        out.put("movements",json.convertValue(payload.path("movements"),List.class));
        JsonNode result=payload.path("result");
        Map<String,Object> projected=new LinkedHashMap<>();
        for(String key:List.of("rounds","reps","timeSeconds","scaled")) if(result.hasNonNull(key)) projected.put(key,json.convertValue(result.get(key),Object.class));
        out.put("result",projected);
      } catch(Exception ex) { throw new IllegalStateException("Invalid stored WOD",ex); }
    } else { out.put("exerciseCount",row.get("exercise_count")); out.put("exercises",publicExercises((String)row.get("payload"))); }
    provenance(out,(UUID)row.get("source_post_id"),viewer);
    return out;
  }
  private static final String SELECT="SELECT p.id,p.author_id,u.handle,p.title,p.published_at,(p.published_at AT TIME ZONE 'UTC')::date AS day,CASE WHEN s.result_schema_version=1 THEN jsonb_array_length(s.payload->'exercises') ELSE NULL END AS exercise_count,s.result_schema_version,s.payload::text AS payload,s.source_post_id FROM activity_post p JOIN app_user u ON u.id=p.author_id JOIN workout_session s ON s.id=p.session_id WHERE ";
  private Map<String,Object> post(UUID id,UUID actor) {
    List<Map<String,Object>> found=db.queryForList(SELECT+DETAIL+" AND p.id=?",actor,actor,actor,actor,id);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return publicRow(found.getFirst(),actor);
  }
  @GetMapping("/posts/{id}") public Map<String,Object> detail(@PathVariable UUID id,HttpServletRequest request) { return post(id,actor(request)); }
  private static final String TEMPLATE_SELECT="SELECT id,title,definition::text AS definition,version,source_post_id FROM workout_template WHERE owner_id=?";
  private Map<String,Object> templateRow(Map<String,Object> row,UUID owner) {
    try {
      Map<String,Object> out=new LinkedHashMap<>();
      out.put("id",row.get("id")); out.put("title",row.get("title"));
      out.put("exercises",json.readTree((String)row.get("definition")).path("exercises"));
      out.put("definitionVersion",1); out.put("version",row.get("version"));
      provenance(out,(UUID)row.get("source_post_id"),owner);
      return out;
    } catch(Exception ex) { throw new IllegalStateException("Invalid stored template",ex); }
  }
  private Map<String,Object> template(UUID id,UUID owner) {
    List<Map<String,Object>> rows=db.queryForList(TEMPLATE_SELECT+" AND id=?",owner,id);
    if(rows.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    return templateRow(rows.getFirst(),owner);
  }
  @GetMapping("/templates") public List<Map<String,Object>> templates(HttpServletRequest request) {
    UUID owner=actor(request);
    return db.queryForList(TEMPLATE_SELECT+" ORDER BY created_at DESC,id DESC LIMIT 50",owner).stream().map(row->templateRow(row,owner)).toList();
  }
  @GetMapping("/templates/{id}") public Map<String,Object> templateDetail(@PathVariable UUID id,HttpServletRequest request) {
    return template(id,actor(request));
  }
  @PostMapping("/posts/{id}/copy") @Transactional
  public ResponseEntity<?> copy(@PathVariable UUID id,HttpServletRequest request) {
    UUID owner=actor(request);
    // Match /posts/{id} rights before even returning an existing idempotent copy.
    List<Map<String,Object>> found=db.queryForList(SELECT+DETAIL+" AND p.id=?",owner,owner,owner,owner,id);
    if(found.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    Map<String,Object> source=found.getFirst();
    if(((Number)source.get("result_schema_version")).intValue()!=1) throw error(HttpStatus.BAD_REQUEST);
    String title=(String)source.get("title");
    String definition;
    try { definition=json.writeValueAsString(Map.of("title",title,"exercises",publicExercises((String)source.get("payload")))); }
    catch(Exception ex) { throw new IllegalStateException(ex); }
    UUID templateId=UUID.randomUUID();
    int inserted=db.update("INSERT INTO workout_template(id,owner_id,source_post_id,title,definition) VALUES(?,?,?,?,?::jsonb) ON CONFLICT(owner_id,source_post_id) DO NOTHING",templateId,owner,id,title,definition);
    if(inserted==0) templateId=db.queryForObject("SELECT id FROM workout_template WHERE owner_id=? AND source_post_id=?",UUID.class,owner,id);
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(template(templateId,owner));
  }
  @PutMapping("/templates/{id}") public Map<String,Object> editTemplate(@PathVariable UUID id,@RequestBody TemplateDefinition in,HttpServletRequest request) {
    UUID owner=actor(request);
    // Do not reveal validation errors for someone else's template.
    template(id,owner);
    if(in==null) throw error(HttpStatus.BAD_REQUEST);
    validate(new Workout(UUID.randomUUID(),in.title(),in.exercises()));
    String payload;
    try { payload=json.writeValueAsString(in); } catch(Exception ex) { throw error(HttpStatus.BAD_REQUEST); }
    db.update("UPDATE workout_template SET title=?,definition=?::jsonb,version=version+1 WHERE id=? AND owner_id=?",in.title().strip(),payload,id,owner);
    return template(id,owner);
  }
  @PostMapping("/templates/{id}/sessions") @Transactional
  public ResponseEntity<?> startTemplate(@PathVariable UUID id,@RequestBody StartTemplate in,HttpServletRequest request) {
    UUID owner=actor(request);
    List<Map<String,Object>> rows=db.queryForList(TEMPLATE_SELECT+" AND id=?",owner,id);
    if(rows.isEmpty()) throw error(HttpStatus.NOT_FOUND);
    if(in==null || in.clientId()==null) throw error(HttpStatus.BAD_REQUEST);
    Map<String,Object> source=rows.getFirst();
    TemplateDefinition definition;
    try { definition=json.readValue((String)source.get("definition"),TemplateDefinition.class); }
    catch(Exception ex) { throw new IllegalStateException("Invalid stored template",ex); }
    Workout workout=new Workout(in.clientId(),definition.title(),definition.exercises());
    validate(workout);
    UUID sessionId=UUID.randomUUID();
    int inserted=db.update("INSERT INTO workout_session(id,owner_id,client_id,title,payload,source_post_id) VALUES(?,?,?,?,?::jsonb,?) ON CONFLICT(owner_id,client_id) DO NOTHING",sessionId,owner,in.clientId(),workout.title(),encode(workout),source.get("source_post_id"));
    if(inserted==0) sessionId=db.queryForObject("SELECT id FROM workout_session WHERE owner_id=? AND client_id=?",UUID.class,owner,in.clientId());
    return ResponseEntity.status(inserted==1?HttpStatus.CREATED:HttpStatus.OK).body(session(sessionId,owner));
  }
  @GetMapping("/feed") public List<Map<String,Object>> feed(HttpServletRequest request,@RequestParam(defaultValue="0") int offset) {
    UUID user=actor(request); if(offset<0 || offset>1000) throw error(HttpStatus.BAD_REQUEST);
    return db.queryForList(SELECT+DISCOVER+" ORDER BY p.published_at DESC,p.id DESC LIMIT 20 OFFSET ?",user,user,offset).stream().map(row->publicRow(row,user)).toList();
  }
  private Object[] cursor(String value) {
    if(value==null) return null;
    try {
      if(value.length()>150) throw new IllegalArgumentException();
      String[] parts=new String(Base64.getUrlDecoder().decode(value),StandardCharsets.UTF_8).split("\\|",-1);
      if(parts.length!=2) throw new IllegalArgumentException();
      return new Object[]{Timestamp.from(Instant.parse(parts[0])),UUID.fromString(parts[1])};
    } catch(IllegalArgumentException ex) { throw error(HttpStatus.BAD_REQUEST); }
  }
  private Map<String,Object> page(String filter,List<Object> params,int limit,String after,UUID viewer) {
    if(limit<1 || limit>20) throw error(HttpStatus.BAD_REQUEST);
    Object[] cursor=cursor(after);
    String sql=SELECT+filter+(cursor==null?"":" AND (p.published_at,p.id)<(?,?)")+" ORDER BY p.published_at DESC,p.id DESC LIMIT ?";
    if(cursor!=null) { params.add(cursor[0]); params.add(cursor[1]); }
    params.add(limit+1);
    List<Map<String,Object>> rows=db.queryForList(sql,params.toArray());
    boolean more=rows.size()>limit;
    List<Map<String,Object>> items=rows.subList(0,Math.min(rows.size(),limit));
    Map<String,Object> result=new LinkedHashMap<>();
    result.put("items",items.stream().map(row->publicRow(row,viewer)).toList());
    Map<String,Object> last=items.isEmpty()?null:items.getLast();
    result.put("nextCursor",more && last!=null?Base64.getUrlEncoder().withoutPadding().encodeToString(( ((Timestamp)last.get("published_at")).toInstant()+"|"+last.get("id")).getBytes(StandardCharsets.UTF_8)):null);
    return result;
  }
  @GetMapping("/feed/following") public Map<String,Object> following(HttpServletRequest request,@RequestParam(defaultValue="20") int limit,@RequestParam(required=false) String cursor) {
    UUID user=actor(request);
    return page(VISIBLE+" AND "+ACCEPTED+" AND p.audience IN ('PUBLIC','FOLLOWERS')",new ArrayList<>(List.of(user,user,user)),limit,cursor,user);
  }
  @GetMapping("/users/{id}/posts") public Map<String,Object> profilePosts(@PathVariable UUID id,HttpServletRequest request,@RequestParam(defaultValue="20") int limit,@RequestParam(required=false) String cursor) {
    UUID user=actor(request);
    // Same post-level predicate as detail: no private-account bypass through profile browsing.
    profile(id,request);
    if(!id.equals(user) && db.queryForObject("SELECT count(*) FROM app_user WHERE id=? AND is_private",Integer.class,id)>0 &&
      db.queryForObject("SELECT count(*) FROM user_follow WHERE follower_id=? AND followed_id=? AND status='ACCEPTED'",Integer.class,user,id)==0) throw error(HttpStatus.NOT_FOUND);
    return page(DETAIL+" AND p.author_id=?",new ArrayList<>(List.of(user,user,user,user,id)),limit,cursor,user);
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
