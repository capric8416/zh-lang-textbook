use super::auth::current_account;
use crate::*;
use serde::Deserialize;
use worker::{Env, Request, Response, Result};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PasswordChange {
    old_verifier: String,
    new_salt: String,
    new_iterations: u32,
    new_verifier: String,
}

pub(super) async fn get(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let db = env.d1("DB")?;
    let class = crate::db::class_memberships::find_for_student(&db, &user.id).await?;
    Response::from_json(
        &serde_json::json!({"account":crate::db::accounts::view(&user),"class":class}),
    )
}

pub(super) async fn change_password(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let input: PasswordChange = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    if !constant_time_eq(
        verifier_hash(&input.old_verifier)
            .unwrap_or_default()
            .as_bytes(),
        user.password_hash.as_bytes(),
    ) {
        return error("current password is incorrect", 403);
    }
    if !valid_password_parameters(&input.new_salt, input.new_iterations)
        || verifier_hash(&input.new_verifier).is_none()
    {
        return error("invalid password verifier parameters", 400);
    }
    let db = env.d1("DB")?;
    crate::db::accounts::set_password(
        &db,
        &user.id,
        &input.new_salt,
        &input.new_verifier,
        input.new_iterations,
        false,
    )
    .await?;
    crate::db::sessions::revoke_account(&db, &user.id).await?;
    Response::from_json(&serde_json::json!({"ok":true,"reauthenticate":true}))
}

pub(super) async fn leave_class(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "student" {
        return error("forbidden", 403);
    }
    crate::db::class_memberships::leave(&env.d1("DB")?, &user.id).await?;
    Response::from_json(&serde_json::json!({"ok":true}))
}
