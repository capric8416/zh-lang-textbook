use crate::*;
use worker::{Env, Request, Response, Result};

pub(super) async fn create(request: &mut Request, env: &Env) -> Result<Response> {
    let secret = env
        .var("BOOTSTRAP_SECRET")
        .map(|v| v.to_string())
        .unwrap_or_default();
    let supplied = request
        .headers()
        .get("X-Bootstrap-Secret")?
        .unwrap_or_default();
    if secret.len() < 32 || !constant_time_eq(secret.as_bytes(), supplied.as_bytes()) {
        return error("bootstrap unauthorized", 401);
    }
    let input: Credentials = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    if !valid_username(&input.username)
        || !valid_password_parameters(&input.salt, input.iterations)
        || verifier_hash(&input.verifier).is_none()
    {
        return error("invalid username or password", 400);
    }
    let db = env.d1("DB")?;
    let count = crate::db::accounts::count(&db).await?;
    if count != 0 {
        return error("bootstrap is already complete", 409);
    }
    crate::db::accounts::insert(
        &db,
        &input.username,
        input.display_name.as_deref().unwrap_or(&input.username),
        "super_admin",
        None,
        &input.salt,
        &input.verifier,
        input.iterations,
        false,
    )
    .await?;
    Response::from_json(&serde_json::json!({"ok":true}))
}
