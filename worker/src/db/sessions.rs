use crate::data::Account;
use crate::utils::sha256_hex;
use worker::{D1Database, Result};

pub(crate) async fn create(
    db: &D1Database,
    token: &str,
    account_id: &str,
    expires_at: i64,
) -> Result<()> {
    db.prepare("INSERT INTO sessions(token_hash,account_id,expires_at) VALUES(?,?,?)")
        .bind(&[
            sha256_hex(token.as_bytes()).into(),
            account_id.into(),
            (expires_at as f64).into(),
        ])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn find_account(
    db: &D1Database,
    token: &str,
    now: i64,
) -> Result<Option<Account>> {
    db.prepare("SELECT a.* FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE s.token_hash=? AND s.expires_at>? AND a.disabled=0")
        .bind(&[sha256_hex(token.as_bytes()).into(), (now as f64).into()])?
        .first::<Account>(None).await
}

pub(crate) async fn revoke_token(db: &D1Database, token: &str) -> Result<()> {
    db.prepare("DELETE FROM sessions WHERE token_hash=?")
        .bind(&[sha256_hex(token.as_bytes()).into()])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn revoke_account(db: &D1Database, account_id: &str) -> Result<()> {
    db.prepare("DELETE FROM sessions WHERE account_id=?")
        .bind(&[account_id.into()])?
        .run()
        .await?;
    Ok(())
}
