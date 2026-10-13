use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Credentials {
    pub(crate) username: String,
    pub(crate) display_name: Option<String>,
    pub(crate) salt: String,
    pub(crate) iterations: u32,
    pub(crate) verifier: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LoginRequest {
    pub(crate) username: String,
    pub(crate) salt: String,
    pub(crate) iterations: u32,
    pub(crate) verifier: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PasswordParametersRequest {
    pub(crate) username: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PasswordParameters {
    pub(crate) salt: String,
    pub(crate) iterations: u32,
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "snake_case")]
pub(crate) struct Account {
    pub(crate) id: String,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) role: String,
    pub(crate) parent_id: Option<String>,
    pub(crate) password_hash: String,
    pub(crate) password_salt: String,
    pub(crate) password_iterations: u32,
    pub(crate) must_change_password: i64,
    pub(crate) disabled: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AccountView {
    pub(crate) id: String,
    pub(crate) username: String,
    pub(crate) display_name: String,
    pub(crate) role: String,
    pub(crate) parent_id: Option<String>,
    pub(crate) must_change_password: bool,
    pub(crate) disabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) children: Option<Vec<AccountView>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LoginResponse {
    pub(crate) token: String,
    pub(crate) expires_at: i64,
    pub(crate) account: AccountView,
}
