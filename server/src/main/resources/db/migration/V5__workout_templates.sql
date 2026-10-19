CREATE TABLE workout_template (
 id UUID PRIMARY KEY, owner_id UUID NOT NULL REFERENCES app_user(id),
 source_post_id UUID REFERENCES activity_post(id) ON DELETE SET NULL,
 title VARCHAR(100) NOT NULL, definition JSONB NOT NULL,
 definition_version INTEGER NOT NULL DEFAULT 1 CHECK (definition_version=1),
 version INTEGER NOT NULL DEFAULT 1,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(owner_id,source_post_id)
);
CREATE INDEX workout_template_owner_idx ON workout_template(owner_id,created_at DESC);
ALTER TABLE workout_session ADD COLUMN source_post_id UUID REFERENCES activity_post(id) ON DELETE SET NULL;
