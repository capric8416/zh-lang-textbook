use serde::{Deserialize, Serialize};
use worker::{D1Database, Result};

#[derive(Deserialize, Serialize)]
pub(crate) struct TextbookPreference {
    pub(crate) grade: u8,
    pub(crate) semester: String,
}

pub(crate) async fn get(db: &D1Database, account_id: &str) -> Result<Option<TextbookPreference>> {
    db.prepare("SELECT grade,semester FROM textbook_preferences WHERE account_id=?")
        .bind(&[account_id.into()])?
        .first::<TextbookPreference>(None)
        .await
}

pub(crate) async fn save(
    db: &D1Database,
    account_id: &str,
    value: &TextbookPreference,
) -> Result<()> {
    db.prepare("INSERT INTO textbook_preferences(account_id,grade,semester) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET grade=excluded.grade,semester=excluded.semester,updated_at=CURRENT_TIMESTAMP")
        .bind(&[account_id.into(), (value.grade as f64).into(), value.semester.clone().into()])?
        .run().await?;
    Ok(())
}
