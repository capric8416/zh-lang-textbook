use serde::{Deserialize, Serialize};
use worker::{D1Database, Result};

#[derive(Deserialize, Serialize)]
#[serde(rename_all(serialize = "camelCase", deserialize = "snake_case"))]
pub(crate) struct PracticeProgressRow {
    pub(crate) textbook_key: String,
    pub(crate) question_key: String,
    pub(crate) correct_count: i64,
    pub(crate) wrong_count: i64,
    pub(crate) last_correct_at: Option<String>,
    pub(crate) last_wrong_at: Option<String>,
    pub(crate) correct_streak_started_at: Option<String>,
}

#[derive(Deserialize)]
pub(crate) struct PetProfileRow {
    pub(crate) profile_json: String,
    pub(crate) revision: i64,
}

pub(crate) async fn progress(
    db: &D1Database,
    student_id: &str,
) -> Result<Vec<PracticeProgressRow>> {
    db.prepare("SELECT textbook_key,question_key,correct_count,wrong_count,last_correct_at,last_wrong_at,correct_streak_started_at FROM practice_progress WHERE student_id=? ORDER BY textbook_key,question_key")
        .bind(&[student_id.into()])?
        .all()
        .await?
        .results::<PracticeProgressRow>()
}

pub(crate) async fn pet_profile(
    db: &D1Database,
    account_id: &str,
) -> Result<Option<PetProfileRow>> {
    db.prepare("SELECT profile_json,revision FROM pet_profiles WHERE account_id=?")
        .bind(&[account_id.into()])?
        .first::<PetProfileRow>(None)
        .await
}

pub(crate) async fn save_pet_profile(
    db: &D1Database,
    account_id: &str,
    profile_json: &str,
    base_revision: i64,
) -> Result<Option<PetProfileRow>> {
    if base_revision == 0 {
        db.prepare("INSERT INTO pet_profiles(account_id,profile_json,revision) VALUES(?,?,1) ON CONFLICT(account_id) DO NOTHING")
            .bind(&[account_id.into(), profile_json.into()])?
            .run()
            .await?;
    } else {
        db.prepare("UPDATE pet_profiles SET profile_json=?,revision=revision+1,updated_at=CURRENT_TIMESTAMP WHERE account_id=? AND revision=?")
            .bind(&[profile_json.into(), account_id.into(), (base_revision as f64).into()])?
            .run()
            .await?;
    }
    pet_profile(db, account_id).await
}
