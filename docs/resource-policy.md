# Resource authorization / 资源级授权

`require-resource` takes a request loader, a `(principal resource)` predicate and a `(request resource)` handler. Missing identity yields 401; absent or unauthorized resources yield the same 404. Only exactly `#t` grants access. The handler receives the checked object. For writes, enforce ownership again in the same database transaction or use an ownership-constrained SQL statement; this guard alone does not prevent time-of-check/time-of-use races. Keep CSRF middleware on unsafe routes. Loader and policy exceptions propagate, never grant access.

`require-resource` 接收资源加载器、身份与资源授权谓词、以及接收已授权资源的处理器。未认证返回 401，资源不存在与无权访问均返回 404；仅 `#t` 允许访问。写操作应在同一数据库事务内再次验证归属或使用带归属约束的 SQL，避免检查与使用之间的竞态。写请求仍须启用 CSRF 防护。加载器或授权谓词异常不会授予访问权限。
