# Rust Cloudflare Worker + D1 账号服务

Worker 按 `totp-authenticator/cloudflare/worker` 的 Rust `worker-rs` 结构组织，D1 schema 在 `migrations/`。客户端用随机盐和 PBKDF2-HMAC-SHA256 派生 32 字节 verifier；Worker 只接收 `salt`、`iterations`、`verifier` 并在 D1 保存 `SHA-256(verifier)`。原始密码不发送给 Worker，session token 也仅以 SHA-256 哈希保存。

## 初始化与部署

```sh
npx wrangler d1 create zh-lang-textbook-accounts --config worker/wrangler.toml
# 将返回的 database_id 写入 wrangler.toml
npx wrangler d1 migrations apply zh-lang-textbook-accounts --remote --config worker/wrangler.toml
npx wrangler secret put BOOTSTRAP_SECRET --config worker/wrangler.toml
cd worker && npx wrangler deploy
```

为 `BOOTSTRAP_SECRET` 设置至少 32 个随机字符。空数据库上只可调用一次 `POST /api/v1/bootstrap` 建立首个超级管理员。用本地脚本交互输入初始密码和 secret，密码不会作为请求字段发送：

```sh
python3 worker/scripts/bootstrap_super_admin.py https://<worker-domain> <username> --display-name '<display-name>'
```

登录先请求 `POST /api/v1/auth/parameters` 获取该账号的 `salt` 和 `iterations`，客户端据此派生 verifier，再向 `/auth/login` 发送 `{username,salt,iterations,verifier}`。注册、管理员创建、密码重置和改密都采用同一组凭据字段；改密同时带 `oldVerifier`。其后由超级管理员创建其余管理员。班级二维码内容为 `join:<opaque-code>`，有效期 7 天，不含个人信息。学习资料仍由 App 本地提供；账号、管理和班级加入功能需要网络。

本地开发：`npx wrangler d1 migrations apply zh-lang-textbook-accounts --local --config worker/wrangler.toml`，再在 `worker/` 下运行 `npx wrangler dev`。

## 源码分层

```text
src/
├── lib.rs                 # Worker 入口与模块声明；不直接操作 D1
├── data.rs                # API/数据库共享数据结构
├── utils.rs               # 密码、随机数、JSON、响应头等通用工具
├── db/                    # 按数据表归组的 D1 repository
│   ├── accounts.rs
│   ├── sessions.rs
│   ├── classes.rs
│   ├── class_memberships.rs
│   ├── class_join_codes.rs
│   └── practice_records.rs
└── v1/                    # 按 /api/v1 路径和业务域组织的 handlers
    ├── mod.rs
    ├── health.rs
    ├── bootstrap.rs
    ├── auth.rs
    ├── me.rs
    ├── accounts.rs
    ├── classes.rs
    └── practice.rs
```

所有 SQL 都位于 `db/`，`v1/` 只负责请求校验、权限规则和调用 repository。

学生个人学习记录：`GET /api/v1/practice/records?limit=100`，仅允许学生读取登录账号自己的所有历史记录，包含历史班级和 `class_id=NULL` 的作答。每页最多 500 条；返回 `records` 和 `nextCursor`，后者非空时将其中的 `beforeTime`、`afterId` 原样作为下一页查询参数。按作答时间倒序、记录 ID 升序分页；查询期间新插入到游标之前的记录会在下次刷新时获取。无需传入学生 ID。部署时应用 `0007_student_practice_history_index.sql` 索引迁移。App 按记录 ID 与本机记录合并，并按账号保存远端缓存供离线查看。

跨设备学习状态：`GET /api/v1/me/study-state` 返回当前学生的聚合学习进度、宠物档案及版本号；`PUT /api/v1/me/pet-profile` 使用 `baseRevision` 乐观并发更新宠物档案，版本不匹配时返回 409。`0008_study_state.sql` 会从现有做题记录回填进度，并通过插入触发器持续更新；重复上传相同记录 ID 不会重复计数。

API 前缀 `/api/v1`：`GET /health`、`POST /bootstrap`、`/auth/{register,login,logout}`、个人资料/改密、账号树、直接下级创建与禁用/重置密码、班级创建、入班码及学生加入/退班。学生答题结果写入 `practice_records`；班级管理员通过 `GET /classes/{classId}/records?limit=100` 按班级读取原始历史记录，单页最多 500 条。响应的 `nextCursor` 非空时，原样携带其中的 `beforeTime`、`afterId`、`snapshotRowId` 请求下一页。首次请求固定该班级的记录快照，后续分页不会混入新上传记录；刷新后才会看到这些新记录。`0010_class_practice_records_cursor.sql` 添加按班级、作答时间和记录 ID 排序的索引。旧版 `offset` 参数暂时保留兼容。查询校验班级归属，但不按当前成员关系过滤，因此退班/转班不会隐藏历史记录。题目聚合、排序和错误率统计由 App 完成。学生注册固定为 student；超级管理员能创建超级管理员和集团管理员，集团管理员创建学校管理员，学校管理员创建班级管理员；每级管理员只能管理直接下级。
# 教材选择同步

应用 `0009_textbook_preferences.sql` 迁移后，所有登录账号可使用
`GET /api/v1/me/textbook-preference` 读取自己的选择，或使用 `PUT`
提交 `{"grade":3,"semester":"a"}`（年级 1–6，学期 a/b）。响应为
`{"selection":...}`，未保存时 selection 为 null。按账号隔离，以最后成功写入为准。
App 在进入教材时保存并异步上传；登录时恢复，离线待同步选择优先上传。
