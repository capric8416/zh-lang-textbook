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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileUpdate {
    display_name: String,
}

pub(super) async fn textbook_preference(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let selection = crate::db::textbook_preferences::get(&env.d1("DB")?, &user.id).await?;
    Response::from_json(&serde_json::json!({"selection": selection}))
}

pub(super) async fn save_textbook_preference(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let input: crate::db::textbook_preferences::TextbookPreference = match read_json(request).await
    {
        Ok(value) => value,
        Err(_) => return error("invalid textbook selection", 400),
    };
    if !(1..=6).contains(&input.grade) || !matches!(input.semester.as_str(), "a" | "b") {
        return error("invalid textbook selection", 400);
    }
    crate::db::textbook_preferences::save(&env.d1("DB")?, &user.id, &input).await?;
    Response::from_json(&serde_json::json!({"selection": input}))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PetProfileUpdate {
    profile: serde_json::Value,
    base_revision: i64,
}

pub(super) async fn study_state(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "student" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    let progress = crate::db::study_state::progress(&db, &user.id).await?;
    let pet = crate::db::study_state::pet_profile(&db, &user.id).await?;
    let (profile, revision) = match pet {
        Some(row) => (
            serde_json::from_str::<serde_json::Value>(&row.profile_json).ok(),
            row.revision,
        ),
        None => (None, 0),
    };
    Response::from_json(&serde_json::json!({
        "progress": progress,
        "petProfile": profile,
        "petRevision": revision
    }))
}

pub(super) async fn save_pet_profile(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "student" {
        return error("forbidden", 403);
    }
    let input: PetProfileUpdate = match read_json(request).await {
        Ok(value) => value,
        Err(_) => return error("invalid pet profile", 400),
    };
    if input.base_revision < 0 || !input.profile.is_object() {
        return error("invalid pet profile", 400);
    }
    let profile_json = serde_json::to_string(&input.profile)?;
    if profile_json.len() > 32_768 {
        return error("pet profile is too large", 400);
    }
    let db = env.d1("DB")?;
    let Some(saved) =
        crate::db::study_state::save_pet_profile(&db, &user.id, &profile_json, input.base_revision)
            .await?
    else {
        return error("pet profile save failed", 500);
    };
    let current = serde_json::from_str::<serde_json::Value>(&saved.profile_json)
        .unwrap_or(serde_json::Value::Null);
    if saved.revision != input.base_revision + 1 || current != input.profile {
        return Response::from_json(&serde_json::json!({
            "error":"pet profile conflict",
            "petProfile":current,
            "petRevision":saved.revision
        }))
        .map(|response| response.with_status(409));
    }
    Response::from_json(&serde_json::json!({
        "petProfile":current,
        "petRevision":saved.revision
    }))
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

pub(super) async fn update_profile(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let input: ProfileUpdate = match read_json(request).await {
        Ok(value) => value,
        Err(_) => return error("invalid request", 400),
    };
    let name = input.display_name.trim();
    if name.is_empty() || name.chars().count() > 40 {
        return error("display name must be 1-40 characters", 400);
    }
    let db = env.d1("DB")?;
    crate::db::accounts::set_display_name(&db, &user.id, name).await?;
    let Some(updated) = crate::db::accounts::find_by_id(&db, &user.id).await? else {
        return error("account not found", 404);
    };
    Response::from_json(&serde_json::json!({"account":crate::db::accounts::view(&updated)}))
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
