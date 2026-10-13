use super::auth::current_account;
use crate::*;
use serde::Deserialize;
use worker::{Env, Request, Response, Result};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateAccount {
    username: String,
    salt: String,
    iterations: u32,
    verifier: String,
    display_name: Option<String>,
    role: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AccountPatch {
    disabled: Option<bool>,
    reset_salt: Option<String>,
    reset_iterations: Option<u32>,
    reset_verifier: Option<String>,
}

pub(super) async fn tree(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role == "student" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    let rows = if user.role == "super_admin" {
        crate::db::accounts::list_tree_all(&db).await?
    } else {
        crate::db::accounts::list_tree_below(&db, &user.id).await?
    };
    let roots: Vec<AccountView> = if user.role == "super_admin" {
        rows.iter()
            .filter(|a| {
                (a.role == "super_admin" || a.role == "student")
                    && a.parent_id
                        .as_deref()
                        .map_or(true, |p| !rows.iter().any(|parent| parent.id == p))
            })
            .map(|a| crate::db::accounts::tree_view(a, &rows))
            .collect()
    } else {
        rows.iter()
            .filter(|a| a.parent_id.as_deref() == Some(user.id.as_str()))
            .map(|a| crate::db::accounts::tree_view(a, &rows))
            .collect()
    };
    Response::from_json(&serde_json::json!({"tree":roots}))
}

pub(super) async fn create(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let input: CreateAccount = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    let allowed = match user.role.as_str() {
        "super_admin" => input.role == "super_admin" || input.role == "group_admin",
        "group_admin" => input.role == "school_admin",
        "school_admin" => input.role == "class_admin",
        _ => false,
    };
    if !allowed {
        return error("cannot create this account role", 403);
    }
    if !valid_username(&input.username)
        || !valid_password_parameters(&input.salt, input.iterations)
        || verifier_hash(&input.verifier).is_none()
    {
        return error("invalid username or password", 400);
    }
    let id = match crate::db::accounts::insert(
        &env.d1("DB")?,
        &input.username,
        input.display_name.as_deref().unwrap_or(&input.username),
        &input.role,
        Some(&user.id),
        &input.salt,
        &input.verifier,
        input.iterations,
        true,
    )
    .await
    {
        Ok(v) => v,
        Err(_) => return error("username already exists or account creation failed", 409),
    };
    Response::from_json(&serde_json::json!({"id":id,"username":input.username,"role":input.role,"mustChangePassword":true})).map(|r|r.with_status(201))
}

pub(super) async fn patch(request: &mut Request, env: &Env, id: &str) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let db = env.d1("DB")?;
    let Some(target) = crate::db::accounts::find_by_id(&db, id).await? else {
        return error("not found", 404);
    };
    let can = target.parent_id.as_deref() == Some(user.id.as_str())
        && ((user.role == "super_admin"
            && (target.role == "super_admin" || target.role == "group_admin"))
            || match user.role.as_str() {
                "group_admin" => target.role == "school_admin",
                "school_admin" => target.role == "class_admin",
                _ => false,
            });
    if !can {
        return error("can only manage direct subordinate accounts", 403);
    }
    let input: AccountPatch = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    if let Some(disabled) = input.disabled {
        crate::db::accounts::set_disabled(&db, id, disabled).await?;
    }
    if input.reset_salt.is_some()
        || input.reset_iterations.is_some()
        || input.reset_verifier.is_some()
    {
        let (Some(salt), Some(iterations), Some(verifier)) = (
            input.reset_salt,
            input.reset_iterations,
            input.reset_verifier,
        ) else {
            return error(
                "resetSalt, resetIterations and resetVerifier are required together",
                400,
            );
        };
        if !valid_password_parameters(&salt, iterations) || verifier_hash(&verifier).is_none() {
            return error("invalid password verifier parameters", 400);
        }
        crate::db::accounts::set_password(&db, id, &salt, &verifier, iterations, true).await?;
        crate::db::sessions::revoke_account(&db, id).await?;
    }
    Response::from_json(&serde_json::json!({"ok":true}))
}
