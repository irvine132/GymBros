-- Additive Slice B: existing users remain discoverable and public by default.
ALTER TABLE app_user ADD COLUMN display_name VARCHAR(60);
ALTER TABLE app_user ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE app_user ADD COLUMN preferred_unit VARCHAR(2) NOT NULL DEFAULT 'kg' CHECK (preferred_unit IN ('kg','lb'));
CREATE TABLE user_follow (
 follower_id UUID NOT NULL REFERENCES app_user(id),
 followed_id UUID NOT NULL REFERENCES app_user(id),
 status VARCHAR(8) NOT NULL CHECK (status IN ('PENDING','ACCEPTED')),
 PRIMARY KEY (follower_id, followed_id),
 CHECK (follower_id <> followed_id)
);
CREATE INDEX user_follow_inbox_idx ON user_follow(followed_id,status);
ALTER TABLE activity_post DROP CONSTRAINT activity_post_audience_check;
ALTER TABLE activity_post ADD CONSTRAINT activity_post_audience_check CHECK (audience IN ('PUBLIC','FOLLOWERS'));
CREATE INDEX activity_post_follow_feed_idx ON activity_post(author_id,published_at DESC,id DESC) WHERE deleted_at IS NULL;
