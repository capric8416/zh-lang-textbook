use crate::db::classes::Class;
use crate::utils::sha256_hex;
use worker::{D1Database, Result};

pub(crate) async fn create(
    db: &D1Database,
    code: &str,
    class_id: &str,
    creator_id: &str,
    expires_at: i64,
) -> Result<()> {
    db.prepare(
        "INSERT INTO class_join_codes(code_hash,class_id,created_by,expires_at) VALUES(?,?,?,?)",
    )
    .bind(&[
        sha256_hex(code.as_bytes()).into(),
        class_id.into(),
        creator_id.into(),
        (expires_at as f64).into(),
    ])?
    .run()
    .await?;
    Ok(())
}

pub(crate) async fn find_valid_class(
    db: &D1Database,
    code: &str,
    now: i64,
) -> Result<Option<Class>> {
    db.prepare("SELECT c.id,c.name FROM class_join_codes j JOIN classes c ON c.id=j.class_id WHERE j.code_hash=? AND j.revoked=0 AND j.expires_at>? AND c.disabled=0")
        .bind(&[sha256_hex(code.as_bytes()).into(), (now as f64).into()])?.first::<Class>(None).await
}
