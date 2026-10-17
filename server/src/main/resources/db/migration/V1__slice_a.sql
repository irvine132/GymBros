CREATE TABLE app_user (
 id UUID PRIMARY KEY, handle VARCHAR(32) NOT NULL, email VARCHAR(254) NOT NULL,
 password_hash VARCHAR(100) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CONSTRAINT handle_unique UNIQUE(handle), CONSTRAINT email_unique UNIQUE(email)
);
CREATE TABLE auth_token (
 digest CHAR(64) PRIMARY KEY, user_id UUID NOT NULL REFERENCES app_user(id),
 expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ
);
CREATE INDEX auth_token_user_idx ON auth_token(user_id);
CREATE TABLE workout_session (
 id UUID PRIMARY KEY, owner_id UUID NOT NULL REFERENCES app_user(id), client_id UUID NOT NULL,
 title VARCHAR(100) NOT NULL, payload JSONB NOT NULL, status VARCHAR(12) NOT NULL DEFAULT 'DRAFT',
 started_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ,
 CONSTRAINT workout_client_unique UNIQUE(owner_id,client_id),
 CONSTRAINT workout_status_check CHECK (status IN ('DRAFT','COMPLETED'))
);
CREATE INDEX workout_owner_idx ON workout_session(owner_id, started_at DESC);
CREATE TABLE activity_post (
 id UUID PRIMARY KEY, author_id UUID NOT NULL REFERENCES app_user(id),
 session_id UUID NOT NULL UNIQUE REFERENCES workout_session(id), title VARCHAR(100) NOT NULL,
 audience VARCHAR(12) NOT NULL DEFAULT 'PUBLIC' CHECK (audience='PUBLIC'),
 published_at TIMESTAMPTZ NOT NULL DEFAULT now(), deleted_at TIMESTAMPTZ
);
CREATE INDEX activity_feed_idx ON activity_post(published_at DESC,id DESC) WHERE deleted_at IS NULL;
CREATE TABLE user_block (
 blocker_id UUID NOT NULL REFERENCES app_user(id), blocked_id UUID NOT NULL REFERENCES app_user(id),
 PRIMARY KEY(blocker_id, blocked_id), CHECK(blocker_id <> blocked_id)
);
CREATE TABLE post_report (
 id UUID PRIMARY KEY, reporter_id UUID NOT NULL REFERENCES app_user(id), post_id UUID NOT NULL REFERENCES activity_post(id),
 reason VARCHAR(300) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(reporter_id, post_id)
);
