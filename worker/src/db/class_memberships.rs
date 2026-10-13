use crate::db::classes::Class;
use worker::{D1Database, Result};

pub(crate) async fn find_for_student(db: &D1Database, student_id: &str) -> Result<Option<Class>> {
    db.prepare("SELECT c.id,c.name FROM class_memberships m JOIN classes c ON c.id=m.class_id WHERE m.student_id=? AND c.disabled=0")
        .bind(&[student_id.into()])?.first::<Class>(None).await
}

pub(crate) async fn assign(db: &D1Database, student_id: &str, class_id: &str) -> Result<()> {
    db.prepare("INSERT INTO class_memberships(student_id,class_id) VALUES(?,?) ON CONFLICT(student_id) DO UPDATE SET class_id=excluded.class_id,joined_at=CURRENT_TIMESTAMP")
        .bind(&[student_id.into(), class_id.into()])?.run().await?;
    Ok(())
}

pub(crate) async fn leave(db: &D1Database, student_id: &str) -> Result<()> {
    db.prepare("DELETE FROM class_memberships WHERE student_id=?")
        .bind(&[student_id.into()])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn find_class_for_student(
    db: &D1Database,
    student_id: &str,
) -> Result<Option<String>> {
    db.prepare("SELECT class_id FROM class_memberships WHERE student_id=?")
        .bind(&[student_id.into()])?
        .first::<String>(Some("class_id"))
        .await
}
