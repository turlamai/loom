# Session privilege transitions

Use `transition-web-session` only after verifying credentials and the existing session's CSRF token. Pass the exact `web-session-ref` object obtained from the request. On success it returns `(list new-id new-state set-cookie-header)`; send the header to the browser. On expiry, revocation or a competing transition it returns `#f`, and the caller must fail closed. Both the session identifier and CSRF secret change, and the old session becomes invalid. Revoke live registry instances and bus subscriptions associated with the old CSRF owner when applicable. Already executing requests are not cancelled by session rotation. Login/logout handlers, credential verification and application authorization remain application responsibilities.

## 会话权限转换

仅在验证凭据和原会话 CSRF Token 后调用 `transition-web-session`，传入本次请求读取的原始 `web-session-ref` 对象。成功返回 `(list new-id new-state set-cookie-header)`，由应用发送 Cookie 响应头。过期、撤销或并发转换失败时返回 `#f`，调用方必须拒绝请求。会话 ID 和 CSRF Secret 同时更新，旧会话失效。使用 Live Registry 或 Pub/Sub 时，还应撤销旧 CSRF owner 关联的实例和订阅。会话轮换不会取消已经执行中的请求。登录登出接口、凭据校验和业务授权仍由应用负责。
