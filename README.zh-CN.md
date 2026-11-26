# Loom

面向 Racket 的现代全栈 Web 框架。

**Human-first. Agent-native. Racket-first.**

当前处于开发阶段，尚未发布。参阅 [架构与路线图](docs/architecture.md)。

官方网站计划使用 https://loom.jrtx.site/ 。

## 命令行（开发预览）

```sh
raco loom new hello
cd hello
raco loom doctor
raco loom inspect --json
raco loom test
raco loom dev
```

## HTML 组件

```racket
(require loom loom/html)
(define-component (welcome name)
  (element 'h1 "Hello, " name))
(html-response (page-layout #:title "Welcome" (welcome "Racket")))
```

受限组件构造器校验元素、属性和 URL，拒绝脚本标签与事件属性。原始 `html-response` X-expression 仅供可信代码使用；本模块不是通用 HTML 清洗器，也不能代替完整安全策略。

## HTTP 工具（开发预览）

`loom/http` 提供 JSON 响应、带大小限制的 JSON 解析、保留重复值的查询参数及请求头读取，以及本地重定向。JSON 大小限制在服务器读取请求体之后生效，仍需独立设置传输层限制；解析异常需应用层处理。

## 表单与安全中间件

`loom/forms` 支持带大小限制的 URL 编码表单并保留重复字段；`loom/security` 提供可选的 `security-headers` 中间件，默认添加 CSP、防嵌入、nosniff 和 Referrer-Policy 响应头，并保留应用显式设置。尚不包含 CSRF、认证、TLS 或传输层限制。

## Cookie

`loom/cookies` 提供读取、设置和删除 Cookie 的工具，默认仅限当前主机，启用 Secure、HttpOnly 和 SameSite=Lax。保留重复的合法请求值，应用需拒绝歧义会话 Cookie。该模块不签名或加密 Cookie；生产环境应使用 HTTPS，非 Secure 配置仅用于本地开发。
