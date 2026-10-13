use crate::data::{Account, AccountView};
use crate::utils::{uuid, verifier_hash};
use wasm_bindgen::JsValue;
use worker::{D1Database, Result};

pub(crate) async fn insert(
    db: &D1Database,
    username: &str,
    display_name: &str,
    role: &str,
    parent_id: Option<&str>,
    salt: &str,
    verifier: &str,
    iterations: u32,
    must_change: bool,
) -> Result<String> {
    let id = uuid();
    let Some(hash) = verifier_hash(verifier) else {
        return Err(worker::Error::RustError("invalid password verifier".into()));
    };
    let parent_value = parent_id.map(JsValue::from_str).unwrap_or(JsValue::NULL);
    db.prepare("INSERT INTO accounts(id,username,display_name,role,parent_id,password_hash,password_salt,password_iterations,must_change_password) VALUES(?,?,?,?,?,?,?,?,?)")
        .bind(&[
            id.clone().into(), username.trim().into(), display_name.trim().into(), role.into(),
            parent_value, hash.into(), salt.into(),
            (iterations as f64).into(), (if must_change { 1.0 } else { 0.0 }).into(),
        ])?
        .run().await?;
    Ok(id)
}

pub(crate) async fn find_by_username(db: &D1Database, username: &str) -> Result<Option<Account>> {
    db.prepare("SELECT * FROM accounts WHERE username=? COLLATE NOCASE")
        .bind(&[username.trim().into()])?
        .first::<Account>(None)
        .await
}

pub(crate) async fn find_by_id(db: &D1Database, id: &str) -> Result<Option<Account>> {
    db.prepare("SELECT * FROM accounts WHERE id=?")
        .bind(&[id.into()])?
        .first::<Account>(None)
        .await
}

pub(crate) async fn parent_id(db: &D1Database, id: &str) -> Result<String> {
    Ok(db
        .prepare("SELECT parent_id FROM accounts WHERE id=?")
        .bind(&[id.into()])?
        .first::<String>(Some("parent_id"))
        .await?
        .unwrap_or_default())
}

pub(crate) async fn count(db: &D1Database) -> Result<i64> {
    Ok(db
        .prepare("SELECT COUNT(*) AS count FROM accounts")
        .first::<i64>(Some("count"))
        .await?
        .unwrap_or(0))
}

pub(crate) async fn list_tree_all(db: &D1Database) -> Result<Vec<Account>> {
    db.prepare("SELECT a.*,CASE WHEN a.role='student' THEN COALESCE(c.created_by,a.parent_id) ELSE a.parent_id END AS parent_id FROM accounts a LEFT JOIN class_memberships m ON m.student_id=a.id LEFT JOIN classes c ON c.id=m.class_id ORDER BY a.role,a.display_name")
        .all().await?.results::<Account>()
}

pub(crate) async fn list_tree_below(db: &D1Database, root_id: &str) -> Result<Vec<Account>> {
    let sql = "WITH RECURSIVE descendants(id) AS (SELECT ? UNION ALL SELECT a.id FROM accounts a JOIN descendants d ON a.parent_id=d.id) SELECT a.*,CASE WHEN a.role='student' THEN c.created_by ELSE a.parent_id END AS parent_id FROM accounts a LEFT JOIN class_memberships m ON m.student_id=a.id LEFT JOIN classes c ON c.id=m.class_id WHERE a.id IN (SELECT id FROM descendants) OR (a.role='student' AND c.created_by IN (SELECT id FROM descendants)) ORDER BY a.role,a.display_name";
    db.prepare(sql)
        .bind(&[root_id.into()])?
        .all()
        .await?
        .results::<Account>()
}

pub(crate) async fn set_disabled(db: &D1Database, id: &str, disabled: bool) -> Result<()> {
    db.prepare("UPDATE accounts SET disabled=?,updated_at=CURRENT_TIMESTAMP WHERE id=?")
        .bind(&[if disabled { 1.0.into() } else { 0.0.into() }, id.into()])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn set_password(
    db: &D1Database,
    id: &str,
    salt: &str,
    verifier: &str,
    iterations: u32,
    must_change: bool,
) -> Result<()> {
    let Some(hash) = verifier_hash(verifier) else {
        return Err(worker::Error::RustError("invalid password verifier".into()));
    };
    db.prepare("UPDATE accounts SET password_hash=?,password_salt=?,password_iterations=?,must_change_password=?,updated_at=CURRENT_TIMESTAMP WHERE id=?")
        .bind(&[hash.into(), salt.into(), (iterations as f64).into(),
            (if must_change { 1.0 } else { 0.0 }).into(), id.into()])?.run().await?;
    Ok(())
}

pub(crate) fn view(account: &Account) -> AccountView {
    AccountView {
        id: account.id.clone(),
        username: account.username.clone(),
        display_name: account.display_name.clone(),
        role: account.role.clone(),
        parent_id: account.parent_id.clone(),
        must_change_password: account.must_change_password != 0,
        disabled: account.disabled != 0,
        children: None,
    }
}

pub(crate) fn tree_view(account: &Account, rows: &[Account]) -> AccountView {
    let mut value = view(account);
    value.children = Some(
        rows.iter()
            .filter(|row| row.parent_id.as_deref() == Some(account.id.as_str()))
            .map(|row| tree_view(row, rows))
            .collect(),
    );
    value
}
