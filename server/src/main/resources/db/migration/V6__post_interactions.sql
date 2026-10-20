-- Interactions are additive; historical publications and sessions are untouched.
CREATE TABLE post_like (
 post_id UUID NOT NULL REFERENCES activity_post(id),
 actor_id UUID NOT NULL REFERENCES app_user(id),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(post_id,actor_id)
);
CREATE TABLE post_comment (
 id UUID PRIMARY KEY,
 post_id UUID NOT NULL REFERENCES activity_post(id),
 author_id UUID NOT NULL REFERENCES app_user(id),
 text VARCHAR(500) NOT NULL CHECK(length(trim(text)) BETWEEN 1 AND 500),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 deleted_at TIMESTAMPTZ
);
CREATE INDEX post_comment_page_idx ON post_comment(post_id,created_at DESC,id DESC) WHERE deleted_at IS NULL;
