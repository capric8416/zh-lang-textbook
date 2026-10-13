use serde::{Deserialize, Serialize};
use worker::{D1Database, Result};

#[derive(Deserialize, Serialize)]
#[serde(rename_all(serialize = "camelCase", deserialize = "snake_case"))]
pub(crate) struct BlacklistedStudent {
    pub(crate) student_id: String,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) removed_at: String,
}

pub(crate) async fn contains(db: &D1Database, class_id: &str, student_id: &str) -> Result<bool> {
    Ok(db
        .prepare("SELECT 1 AS found FROM class_blacklist WHERE class_id=? AND student_id=?")
        .bind(&[class_id.into(), student_id.into()])?
        .first::<i64>(Some("found"))
        .await?
        .is_some())
}

pub(crate) async fn list_for_class(
    db: &D1Database,
    class_id: &str,
) -> Result<Vec<BlacklistedStudent>> {
    db.prepare("SELECT b.student_id,a.username,a.display_name,b.created_at AS removed_at FROM class_blacklist b JOIN accounts a ON a.id=b.student_id WHERE b.class_id=? ORDER BY b.created_at DESC")
        .bind(&[class_id.into()])?
        .all()
        .await?
        .results::<BlacklistedStudent>()
}

pub(crate) async fn add(
    db: &D1Database,
    class_id: &str,
    student_id: &str,
    removed_by: &str,
) -> Result<()> {
    db.prepare("INSERT INTO class_blacklist(class_id,student_id,removed_by) VALUES(?,?,?) ON CONFLICT(class_id,student_id) DO UPDATE SET removed_by=excluded.removed_by,created_at=CURRENT_TIMESTAMP")
        .bind(&[class_id.into(), student_id.into(), removed_by.into()])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn remove(db: &D1Database, class_id: &str, student_id: &str) -> Result<()> {
    db.prepare("DELETE FROM class_blacklist WHERE class_id=? AND student_id=?")
        .bind(&[class_id.into(), student_id.into()])?
        .run()
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::BlacklistedStudent;

    #[test]
    fn maps_database_columns_to_api_fields() {
        let student: BlacklistedStudent = serde_json::from_str(
            r#"{"student_id":"student-id","username":"student01","display_name":"小明","removed_at":"2026-10-13 00:00:00"}"#,
        )
        .unwrap();
        let response = serde_json::to_value(student).unwrap();

        assert_eq!(response["studentId"], "student-id");
        assert_eq!(response["displayName"], "小明");
        assert_eq!(response["removedAt"], "2026-10-13 00:00:00");
    }
}
