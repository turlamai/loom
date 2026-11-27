# Authentication demo / 认证示例

Run `LOOM_DEMO_PASSWORD=local-test-password-only racket examples/auth-demo/app.rkt`. This loopback-only example provisions one account (`alice`) from an environment variable. GET `/session` initializes the cookie and returns a CSRF token. POST `/login` with JSON username/password and `X-Loom-CSRF` rotates the cookie and token. GET `/account` requires the member role. POST `/logout` with the current token invalidates the session. Run `bash examples/auth-demo/smoke.sh` for real HTTP integration tests covering login, CSRF, old session rejection, independent clients, logout and throttling.

运行 `LOOM_DEMO_PASSWORD=local-test-password-only racket examples/auth-demo/app.rkt`。此示例仅监听本地回环地址，使用环境变量初始化测试账户 `alice`。GET `/session` 建立会话并返回 CSRF；POST `/login` 提交 JSON 用户名和密码及 CSRF 请求头，成功后轮换会话与令牌；GET `/account` 需要 member 角色；POST `/logout` 撤销会话。执行 `bash examples/auth-demo/smoke.sh` 验证真实 HTTP 登录、CSRF、旧会话失效、客户端隔离、登出及限流。

This is not a production identity service: no registration, persistent account database, MFA or password recovery; local HTTP uses development cookies. Production requires HTTPS, secure cookies, trusted source attribution, durable user storage, request admission and distributed rate limits as appropriate. / 此示例不是生产身份服务：不包含注册、持久化用户库、多因素认证或密码找回；本地 HTTP 使用开发 Cookie。生产环境需要 HTTPS、安全 Cookie、可信来源识别、持久化用户存储及适当的请求准入和分布式限流。
