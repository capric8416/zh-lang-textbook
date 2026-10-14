use serde::{Deserialize, Serialize};
use worker::{D1Database, Result};

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Class {
    pub(crate) id: String,
    pub(crate) name: String,
}

pub(crate) async fn create(
    db: &D1Database,
    id: &str,
    name: &str,
    owner_id: &str,
    school_admin_id: &str,
) -> Result<()> {
    db.prepare("INSERT INTO classes(id,name,created_by,school_admin_id) VALUES(?,?,?,?)")
        .bind(&[
            id.into(),
            name.into(),
            owner_id.into(),
            school_admin_id.into(),
        ])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn list_for_admin(db: &D1Database, owner_id: &str) -> Result<Vec<Class>> {
    db.prepare("SELECT id,name FROM classes WHERE created_by=? ORDER BY created_at DESC")
        .bind(&[owner_id.into()])?
        .all()
        .await?
        .results::<Class>()
}

pub(crate) async fn exists_for_admin(db: &D1Database, id: &str, owner_id: &str) -> Result<bool> {
    Ok(db
        .prepare("SELECT id FROM classes WHERE id=? AND created_by=? AND disabled=0")
        .bind(&[id.into(), owner_id.into()])?
        .first::<String>(Some("id"))
        .await?
        .is_some())
}

pub(crate) async fn set_name(db: &D1Database, id: &str, owner_id: &str, name: &str) -> Result<()> {
    db.prepare("UPDATE classes SET name=? WHERE id=? AND created_by=? AND disabled=0")
        .bind(&[name.into(), id.into(), owner_id.into()])?
        .run()
        .await?;
    Ok(())
}
