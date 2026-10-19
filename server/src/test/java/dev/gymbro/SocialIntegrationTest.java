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
class SocialIntegrationTest {
  @Autowired TestRestTemplate http;
  record User(String token, String id, String handle) {}
  HttpEntity<Object> req(Object body, String token) {
    HttpHeaders h=new HttpHeaders(); h.setContentType(MediaType.APPLICATION_JSON);
    if(token!=null) h.setBearerAuth(token);
    return new HttpEntity<>(body,h);
  }
  ResponseEntity<Map> call(HttpMethod method,String path,Object body,String token) {
    return http.exchange("/api/v1"+path,method,req(body,token),Map.class);
  }
  Map<?,?> ok(HttpMethod method,String path,Object body,String token,HttpStatus code) {
    var r=call(method,path,body,token); assertThat(r.getStatusCode()).as(method+" "+path).isEqualTo(code); return r.getBody();
  }
  User user(String name) {
    String handle=name+UUID.randomUUID().toString().substring(0,8);
    var r=ok(HttpMethod.POST,"/auth/register",Map.of("handle",handle,"email",handle+"@example.test","password","local-demo-test-password"),null,HttpStatus.CREATED);
    return new User(r.get("token").toString(),r.get("userId").toString(),handle);
  }
  String publish(User u,String title,String audience) {
    var s=ok(HttpMethod.POST,"/sessions",Map.of("clientId",UUID.randomUUID().toString(),"title",title,"exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",5,"weight",60,"unit","kg"))))),u.token(),HttpStatus.CREATED);
    String id=s.get("id").toString(); ok(HttpMethod.POST,"/sessions/"+id+"/complete",Map.of(),u.token(),HttpStatus.OK);
    return ok(HttpMethod.POST,"/sessions/"+id+"/posts",Map.of("audience",audience),u.token(),HttpStatus.CREATED).get("id").toString();
  }
  String following(User viewer) { return http.exchange("/api/v1/feed/following",HttpMethod.GET,req(null,viewer.token()),String.class).getBody(); }
  String discover(User viewer) { return http.exchange("/api/v1/feed",HttpMethod.GET,req(null,viewer.token()),String.class).getBody(); }
  @Test void publicPrivateRequestsBlockPrivacyAndPagination() {
    User a=user("alice"), b=user("bravo"), c=user("charlie");
    ok(HttpMethod.PUT,"/me/profile",Map.of("displayName","Athlète A","private",false,"unit","lb"),a.token(),HttpStatus.OK);
    ok(HttpMethod.PUT,"/me/profile",Map.of("displayName","Athlète B","private",true,"unit","kg"),b.token(),HttpStatus.OK);
    assertThat(http.exchange("/api/v1/users?query=Athl",HttpMethod.GET,req(null,c.token()),String.class).getBody()).contains(a.handle(),b.handle()).doesNotContain("email","password_hash");
    assertThat(call(HttpMethod.GET,"/users/"+b.id(),null,c.token()).getBody().toString()).contains("private=true").doesNotContain("email");
    assertThat(call(HttpMethod.POST,"/users/"+a.id()+"/follow",Map.of(),a.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    ok(HttpMethod.POST,"/users/"+a.id()+"/follow",Map.of(),c.token(),HttpStatus.OK);
    ok(HttpMethod.POST,"/users/"+a.id()+"/follow",Map.of(),c.token(),HttpStatus.OK);
    String ap=publish(a,"PublicA", "PUBLIC");
    assertThat(following(c)).contains("PublicA");
    ok(HttpMethod.DELETE,"/users/"+a.id()+"/follow",null,c.token(),HttpStatus.OK);
    assertThat(following(c)).doesNotContain("PublicA");
    String bp=publish(b,"PrivateB", "PUBLIC");
    assertThat(discover(c)).doesNotContain("PrivateB");
    assertThat(call(HttpMethod.GET,"/posts/"+bp,null,c.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/users/"+b.id()+"/posts",null,c.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+b.id()+"/follow",Map.of(),a.token(),HttpStatus.ACCEPTED);
    assertThat(following(a)).doesNotContain("PrivateB");
    assertThat(call(HttpMethod.POST,"/follow-requests/"+a.id()+"/accept",Map.of(),c.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/follow-requests/"+a.id()+"/accept",Map.of(),b.token(),HttpStatus.OK);
    assertThat(following(a)).contains("PrivateB");
    assertThat(call(HttpMethod.GET,"/posts/"+bp,null,a.token()).getStatusCode()).isEqualTo(HttpStatus.OK);
    String followerPost=publish(b,"FollowerB", "FOLLOWERS");
    assertThat(following(a)).contains("FollowerB");
    assertThat(discover(a)).doesNotContain("FollowerB");
    assertThat(call(HttpMethod.GET,"/posts/"+followerPost,null,c.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+a.id()+"/block",Map.of(),b.token(),HttpStatus.CREATED);
    assertThat(following(a)).doesNotContain("PrivateB","FollowerB");
    assertThat(call(HttpMethod.GET,"/posts/"+bp,null,a.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/users/"+b.id(),null,a.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/posts/"+ap,null,c.token()).getStatusCode()).isEqualTo(HttpStatus.OK);
    ok(HttpMethod.POST,"/users/"+a.id()+"/follow",Map.of(),c.token(),HttpStatus.OK);
    String first=publish(a,"FirstPage", "PUBLIC"), second=publish(a,"SecondPage", "PUBLIC");
    var page=ok(HttpMethod.GET,"/feed/following?limit=1",null,c.token(),HttpStatus.OK);
    assertThat(page.get("items").toString()).contains(second).doesNotContain(first);
    String cursor=page.get("nextCursor").toString();
    var next=ok(HttpMethod.GET,"/feed/following?limit=1&cursor="+cursor,null,c.token(),HttpStatus.OK);
    assertThat(next.get("items").toString()).contains(first).doesNotContain(second);
    assertThat(call(HttpMethod.GET,"/feed/following?cursor=bad",null,c.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
  }
  @Test void rejectionAndPrivacyToggleNeverExposeHistoricalPublicPosts() {
    User owner=user("delta"), viewer=user("echo"), stranger=user("foxtrot");
    String id=publish(owner,"OriginallyPublic", "PUBLIC");
    assertThat(discover(stranger)).contains("OriginallyPublic");
    ok(HttpMethod.PUT,"/me/profile",Map.of("displayName","Privé","private",true,"unit","kg"),owner.token(),HttpStatus.OK);
    assertThat(discover(stranger)).doesNotContain("OriginallyPublic");
    assertThat(call(HttpMethod.GET,"/posts/"+id,null,stranger.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/users/"+owner.id()+"/posts",null,stranger.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/users/"+owner.id()+"/posts",null,owner.token()).getStatusCode()).isEqualTo(HttpStatus.OK);
    ok(HttpMethod.POST,"/users/"+owner.id()+"/follow",Map.of(),viewer.token(),HttpStatus.ACCEPTED);
    assertThat(http.exchange("/api/v1/me/follow-requests",HttpMethod.GET,req(null,owner.token()),String.class).getBody()).contains(viewer.handle());
    assertThat(call(HttpMethod.POST,"/follow-requests/"+viewer.id()+"/reject",Map.of(),stranger.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/follow-requests/"+viewer.id()+"/reject",Map.of(),owner.token(),HttpStatus.OK);
    assertThat(following(viewer)).doesNotContain("OriginallyPublic");
    assertThat(call(HttpMethod.POST,"/follow-requests/"+viewer.id()+"/accept",Map.of(),owner.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+owner.id()+"/follow",Map.of(),viewer.token(),HttpStatus.ACCEPTED);
    ok(HttpMethod.POST,"/follow-requests/"+viewer.id()+"/accept",Map.of(),owner.token(),HttpStatus.OK);
    assertThat(following(viewer)).contains("OriginallyPublic");
    ok(HttpMethod.DELETE,"/users/"+owner.id()+"/follow",null,viewer.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.GET,"/posts/"+id,null,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+viewer.id()+"/block",Map.of(),owner.token(),HttpStatus.CREATED);
    assertThat(http.exchange("/api/v1/users?query="+viewer.handle(),HttpMethod.GET,req(null,owner.token()),String.class).getBody()).doesNotContain(viewer.id());
    assertThat(call(HttpMethod.POST,"/users/"+viewer.id()+"/follow",Map.of(),owner.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
  }
  @Test void copyEditStartCompletePublishWithRevokedProvenance() {
    User author=user("source"), copier=user("copier"), third=user("outsider");
    String source=publish(author,"Original", "PUBLIC");
    String restricted=publish(author,"Followers only", "FOLLOWERS");
    assertThat(call(HttpMethod.POST,"/posts/"+restricted+"/copy",Map.of(),copier.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.POST,"/posts/"+restricted+"/copy",Map.of(),third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+author.id()+"/follow",Map.of(),copier.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.POST,"/posts/"+restricted+"/copy",Map.of(),copier.token()).getStatusCode()).isEqualTo(HttpStatus.CREATED);
    String path="/posts/"+source+"/copy";
    var copied=ok(HttpMethod.POST,path,Map.of(),copier.token(),HttpStatus.CREATED);
    String id=copied.get("id").toString();
    assertThat(ok(HttpMethod.POST,path,Map.of(),copier.token(),HttpStatus.OK).get("id")).isEqualTo(id);
    assertThat(copied.toString()).contains("Squat", "60",author.handle()).doesNotContain("completedAt","startedAt","clientId","email");
    assertThat(call(HttpMethod.GET,"/templates/"+id,null,third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.PUT,"/templates/"+id,Map.of("title","Steal"),third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.POST,"/templates/"+id+"/sessions",Map.of("clientId",UUID.randomUUID().toString()),third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.PUT,"/templates/"+id,Map.of("title","Invalid","exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",0,"weight",-1,"unit","kg"))))),copier.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    var edited=ok(HttpMethod.PUT,"/templates/"+id,Map.of("title","Mon squat","exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",8,"weight",40,"unit","lb"))))),copier.token(),HttpStatus.OK);
    assertThat(edited.get("version")).isEqualTo(2);
    assertThat(http.exchange("/api/v1/templates",HttpMethod.GET,req(null,copier.token()),String.class).getBody()).contains("Mon squat");
    String clientId=UUID.randomUUID().toString();
    var started=ok(HttpMethod.POST,"/templates/"+id+"/sessions",Map.of("clientId",clientId),copier.token(),HttpStatus.CREATED);
    String session=started.get("id").toString();
    assertThat(ok(HttpMethod.POST,"/templates/"+id+"/sessions",Map.of("clientId",clientId),copier.token(),HttpStatus.OK).get("id")).isEqualTo(session);
    assertThat(started.toString()).contains("Mon squat","lb","40");
    assertThat(call(HttpMethod.GET,"/sessions/"+session,null,third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/sessions/"+session+"/complete",Map.of(),copier.token(),HttpStatus.OK);
    String copyPost=ok(HttpMethod.POST,"/sessions/"+session+"/posts",Map.of("audience","PUBLIC"),copier.token(),HttpStatus.CREATED).get("id").toString();
    assertThat(call(HttpMethod.GET,"/posts/"+source,null,third.token()).getBody().toString()).contains("60").doesNotContain("Mon squat");
    assertThat(call(HttpMethod.GET,"/posts/"+copyPost,null,third.token()).getBody().toString()).contains("Mon squat","sourcePostId",source);
    ok(HttpMethod.DELETE,"/users/"+author.id()+"/follow",null,copier.token(),HttpStatus.OK);
    ok(HttpMethod.PUT,"/me/profile",Map.of("displayName","Privé","private",true,"unit","kg"),author.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.POST,path,Map.of(),third.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.POST,path,Map.of(),copier.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    for (String endpoint : List.of("/templates", "/feed", "/feed/following")) {
      var response=http.exchange("/api/v1"+endpoint,HttpMethod.GET,req(null,copier.token()),String.class);
      assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
      assertThat(response.getBody()).doesNotContain(source,author.handle());
    }
    assertThat(http.exchange("/api/v1/sessions",HttpMethod.GET,req(null,copier.token()),String.class).getBody())
      .doesNotContain(source,author.handle());
    assertThat(call(HttpMethod.GET,"/templates/"+id,null,copier.token()).getBody().toString()).contains("sourceUnavailable=true").doesNotContain(source,author.handle());
    assertThat(call(HttpMethod.GET,"/sessions/"+session,null,copier.token()).getBody().toString()).contains("sourceUnavailable=true").doesNotContain(source,author.handle());
    assertThat(call(HttpMethod.GET,"/posts/"+copyPost,null,third.token()).getBody().toString()).contains("sourceUnavailable=true").doesNotContain(source,author.handle());
    ok(HttpMethod.POST,"/users/"+copier.id()+"/block",Map.of(),author.token(),HttpStatus.CREATED);
    assertThat(call(HttpMethod.POST,path,Map.of(),copier.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
  }
  @Test void crossfitWodDraftResumeFinishAndPublishWithoutStrengthResults() {
    User author=user("wodathlete"), viewer=user("wodviewer");
    String title="WOD "+UUID.randomUUID();
    var input=Map.of("clientId",UUID.randomUUID().toString(),"title",title,"format","AMRAP",
      "timeCapSeconds",720,"movements",List.of("Burpees","Tractions"),
      "result",Map.of("rounds",5,"reps",7,"scaled",false));
    var invalid=new java.util.HashMap<String,Object>(input); invalid.put("timeCapSeconds",0);
    assertThat(call(HttpMethod.POST,"/wods",invalid,author.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    invalid.put("timeCapSeconds",720); invalid.put("format","FOR_TIME");
    assertThat(call(HttpMethod.POST,"/wods",invalid,author.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    invalid.put("format","AMRAP"); invalid.put("result",Map.of("rounds",0,"reps",0,"scaled",false));
    assertThat(call(HttpMethod.POST,"/wods",invalid,author.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    var created=ok(HttpMethod.POST,"/wods",input,author.token(),HttpStatus.CREATED);
    String session=created.get("id").toString();
    assertThat(ok(HttpMethod.POST,"/wods",input,author.token(),HttpStatus.OK).get("id")).isEqualTo(session);
    assertThat(call(HttpMethod.POST,"/sessions",Map.of("clientId",input.get("clientId"),"title","Wrong sport",
      "exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",5,"weight",20,"unit","kg"))))),author.token()).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(created.toString()).contains("AMRAP","Burpees","resultSchemaVersion=2").doesNotContain("weight");
    assertThat(call(HttpMethod.GET,"/sessions/"+session,null,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    var changed=new java.util.HashMap<String,Object>(input);
    changed.put("result",Map.of("rounds",6,"reps",3,"scaled",true));
    ok(HttpMethod.PUT,"/wods/"+session,changed,author.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.PUT,"/sessions/"+session,Map.of("clientId",input.get("clientId"),"title","Wrong sport",
      "exercises",List.of(Map.of("name","Squat","sets",List.of(Map.of("reps",5,"weight",20,"unit","kg"))))),author.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.PUT,"/wods/"+session,changed,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(call(HttpMethod.GET,"/sessions/"+session,null,author.token()).getBody().toString()).contains("rounds=6","scaled=true");
    ok(HttpMethod.POST,"/sessions/"+session+"/complete",Map.of(),author.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.PUT,"/wods/"+session,changed,author.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(discover(viewer)).doesNotContain(title);
    String post=ok(HttpMethod.POST,"/sessions/"+session+"/posts",Map.of("audience","PUBLIC"),author.token(),HttpStatus.CREATED).get("id").toString();
    assertThat(discover(viewer)).contains(title,"AMRAP","Burpees","rounds","timeCapSeconds").doesNotContain("clientId","startedAt");
    assertThat(call(HttpMethod.GET,"/posts/"+post,null,viewer.token()).getBody().toString()).contains("AMRAP");
    assertThat(call(HttpMethod.POST,"/posts/"+post+"/copy",Map.of(),viewer.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    var timeWod=new java.util.HashMap<String,Object>(input);
    timeWod.put("clientId",UUID.randomUUID().toString()); timeWod.put("format","FOR_TIME");
    timeWod.put("result",Map.of("timeSeconds",610,"scaled",true));
    var timed=ok(HttpMethod.POST,"/wods",timeWod,author.token(),HttpStatus.CREATED);
    assertThat(timed.toString()).contains("FOR_TIME","timeSeconds=610");
    assertThat(((Map)((Map)timed.get("workout")).get("result")).get("rounds")).isNull();
    var emom=new java.util.HashMap<String,Object>(input);
    emom.put("clientId",UUID.randomUUID().toString()); emom.put("format","EMOM");
    assertThat(ok(HttpMethod.POST,"/wods",emom,author.token(),HttpStatus.CREATED).toString()).contains("EMOM");
  }
  @Test void hyroxSegmentsStayPrivateUntilPublishedAndNeverExposeNotes() {
    User athlete=user("hyroxowner"), viewer=user("hyroxviewer");
    String client=UUID.randomUUID().toString();
    var run=Map.of("type","RUN","distanceMeters",1000,"durationSeconds",330);
    var station=Map.of("type","STATION","name","SkiErg","durationSeconds",240,"reps",50,"weight",20,"unit","kg");
    var input=Map.of("clientId",client,"title","Mon Hyrox","totalSeconds",640,
      "segments",List.of(run,station),"notes","Note strictement privée");
    var invalid=new java.util.HashMap<String,Object>(input);
    invalid.put("totalSeconds",100);
    assertThat(call(HttpMethod.POST,"/hyrox",invalid,athlete.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    invalid.put("totalSeconds",640);
    invalid.put("segments",List.of(Map.of("type","RUN","distanceMeters",-1,"durationSeconds",330),station));
    assertThat(call(HttpMethod.POST,"/hyrox",invalid,athlete.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    invalid.put("segments",List.of(run,Map.of("type","STATION","name","SkiErg","durationSeconds",240,"weight",20,"unit","stone")));
    assertThat(call(HttpMethod.POST,"/hyrox",invalid,athlete.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    var created=ok(HttpMethod.POST,"/hyrox",input,athlete.token(),HttpStatus.CREATED);
    String id=created.get("id").toString();
    assertThat(created.toString()).contains("resultSchemaVersion=3","SkiErg","Note strictement privée");
    assertThat(ok(HttpMethod.POST,"/hyrox",input,athlete.token(),HttpStatus.OK).get("id")).isEqualTo(id);
    assertThat(call(HttpMethod.POST,"/wods",Map.of("clientId",client,"title","Cross sport","format","AMRAP",
      "timeCapSeconds",720,"movements",List.of("Burpees"),"result",Map.of("rounds",3,"reps",2,"scaled",false)),athlete.token()).getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(call(HttpMethod.GET,"/sessions/"+id,null,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    var changed=new java.util.HashMap<String,Object>(input); changed.put("totalSeconds",700);
    assertThat(call(HttpMethod.PUT,"/hyrox/"+id,changed,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.PUT,"/hyrox/"+id,changed,athlete.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.PUT,"/wods/"+id,Map.of(),athlete.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    ok(HttpMethod.POST,"/sessions/"+id+"/complete",Map.of(),athlete.token(),HttpStatus.OK);
    assertThat(call(HttpMethod.PUT,"/hyrox/"+id,changed,athlete.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(discover(viewer)).doesNotContain("Mon Hyrox");
    String post=ok(HttpMethod.POST,"/sessions/"+id+"/posts",Map.of("audience","PUBLIC"),athlete.token(),HttpStatus.CREATED).get("id").toString();
    for(String response:List.of(discover(viewer),call(HttpMethod.GET,"/posts/"+post,null,viewer.token()).getBody().toString())) {
      assertThat(response).contains("HYROX","SkiErg","distanceMeters","totalSeconds","700")
        .doesNotContain("Note strictement privée","clientId","startedAt","completedAt");
    }
    assertThat(call(HttpMethod.POST,"/posts/"+post+"/copy",Map.of(),viewer.token()).getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
    ok(HttpMethod.PUT,"/me/profile",Map.of("displayName","Privé","private",true,"unit","kg"),athlete.token(),HttpStatus.OK);
    assertThat(discover(viewer)).doesNotContain("Mon Hyrox","Note strictement privée");
    assertThat(call(HttpMethod.GET,"/posts/"+post,null,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
    ok(HttpMethod.POST,"/users/"+athlete.id()+"/follow",Map.of(),viewer.token(),HttpStatus.ACCEPTED);
    assertThat(following(viewer)).doesNotContain("Mon Hyrox");
    ok(HttpMethod.POST,"/follow-requests/"+viewer.id()+"/accept",Map.of(),athlete.token(),HttpStatus.OK);
    assertThat(following(viewer)).contains("Mon Hyrox","SkiErg").doesNotContain("Note strictement privée");
    ok(HttpMethod.POST,"/users/"+viewer.id()+"/block",Map.of(),athlete.token(),HttpStatus.CREATED);
    assertThat(following(viewer)).doesNotContain("Mon Hyrox");
    assertThat(call(HttpMethod.GET,"/posts/"+post,null,viewer.token()).getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
  }
}
