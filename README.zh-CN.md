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

## 会话

`loom/session` 提供有容量限制、同步访问的内存会话存储，支持安全随机 ID、绝对过期、删除与轮换。应使用不可变会话数据，存储不会复制对象。重启会丢失会话，不支持跨进程共享；Cookie 绑定、认证、CSRF 与分布式存储尚未实现。

## 数据库（开发预览）

`loom/db` 复用 Racket 官方数据库库，提供 SQLite、PostgreSQL 连接、连接资源清理、显式事务及参数化查询。已添加 SQLite 提交与回滚测试；PostgreSQL 集成、连接池和迁移尚未验证。生产环境需配置 TLS，凭据不得写入源码。

## 数据库迁移（开发预览）

`loom/migrate` 在事务中按连续版本执行迁移，并记录版本和描述。重复执行相同计划不再应用，拒绝截断或修改描述的历史。迁移应由单一部署进程执行，迁移代码必须可信且不得自行提交事务。尚不支持内容校验和、向下迁移及分布式锁；SQLite 已添加回滚测试，PostgreSQL 待集成验证。

## 数据模型（开发预览）

```racket
(require loom/model)
(define-model user [name string #t] [age integer #f])
(validate-model user (hasheq 'name "Alice")) ; => '()
(model-schema user)
```

支持必填字段、基础类型、未知字段拒绝及 JSON Schema 元数据；尚不生成 SQL、不持久化、不自动转换输入、不承担授权。敏感字段应使用独立的输入和输出模型。

## 模型持久化（开发预览）

`loom/repository` 将声明式模型映射到现有 SQLite 表，支持 `make-repository`、增删改查与有界分页。主键必须显式声明为必填字符串或整数，使用迁移创建表。更新替换全部非主键字段，缺失可选字段写入 SQL NULL，数据值使用参数化查询。暂不支持自动主键、授权、关系及 PostgreSQL 持久化适配。

## 全栈示例

参阅 [Taskboard](examples/taskboard/README.zh-CN.md)，包含本地 SQLite 应用与真实 HTTP 验收测试，尚不适用于生产多用户部署。

## Web 会话与 CSRF（开发预览）

`loom/session-http` 将服务端会话绑定到仅限当前主机的 Cookie，并为每个会话生成随机 CSRF 令牌。`start-web-session` 返回 ID、状态和 Cookie 响应头；应用显式附加响应头并在写操作前校验令牌。`end-web-session` 撤销会话并返回清除响应头。拒绝重复或畸形会话 Cookie。生产默认要求 HTTPS。该模块并非认证或自动中间件，应用仍需实施授权、令牌页面禁止缓存及所有相关写操作的 CSRF 校验。存储仍为单进程内存。

`loom/csrf-middleware` 为非安全 HTTP 方法提供可选的 URL 编码表单防护，通过 `current-verified-form` 提供校验后的字段。安全方法必须只读；Taskboard 演示独立浏览器会话和禁止缓存响应。JSON API 需单独策略。

## Live Components（运行时预览）

`loom/live` 提供 `make-live-component`、`live-mount`、`live-snapshot` 和 `live-dispatch!`。组件定义初始状态工厂、纯渲染函数及显式事件处理器。实例独立维护版本并串行更新，过期版本和未知事件不修改状态，渲染失败不提交新状态。应使用不可变状态、执行时间有界且不重入同一实例的纯回调。浏览器通信、会话归属、生命周期限制和 DOM 更新尚未实现。

`loom/live-registry` 提供按会话归属隔离的实例 ID、绝对过期、全局及单归属容量限制、显式卸载与归属撤销。归属标识必须来自可信服务端会话上下文。当前操作共享注册表锁（包括渲染），回调必须有界且不可重入。注册表仅限单进程，登出时应用必须显式撤销归属。尚未接入 HTTP 通信。

`loom/live-http` 提供 POST JSON 事件处理器，包含会话与 CSRF 校验、实例归属、版本冲突、缓冲后请求大小限制和结构化渲染树。挂载时使用已验证会话的 `web-session-csrf` 作为内部归属键，不接受客户端指定归属。应使用独立 JSON 路由，不经过 URL 编码表单中间件。响应禁止缓存。浏览器运行时、自动撤销、传输层限制和服务端推送尚未实现。

### 浏览器运行时预览

`loom/assets/live.mjs` 提供 `attachLive(root, {endpoint, id, version, csrf})`。捕获 `button[data-live-event]` 的事件，发送同源 JSON 请求，处理过期版本且不自动重放，通过校验后的 DOM 节点原地协调组件子树，不插入 HTML 字符串。仅支持保守的片段子集；同一时刻仅允许一个请求，额外事件会丢弃。应用需自行提供模块资源及会话初始化配置。Node 测试使用 DOM 桩，不是真实浏览器；使用 `data-live-key` 标识同级稳定节点；兼容节点原地复用，服务端默认值不变时保留本地编辑，默认值变化时重置控件。节点移动或不兼容替换仍可能丢失焦点，并非完整虚拟 DOM 或受控表单实现。服务端推送及重连尚待实现。

### Live Counter

执行 `racket examples/live-counter/app.rkt` 后打开 http://127.0.0.1:8080/。本地示例提供浏览器运行时、会话隔离的计数器及无需页面导航的组件更新。CI 已配置 HTTP 冒烟与 Chromium 验收。刷新页面创建新实例，过期实例在后续注册表访问时回收。尚不适用于生产部署。

### Live 状态恢复

`make-live-snapshot-handler` 提供只读 POST JSON 接口，接收 `{id}`，使用与事件请求相同的会话 Cookie 和 `X-Loom-CSRF` 请求头。在 `attachLive` 中配置 `snapshotEndpoint`，通过 `client.resync()` 在网络结果不确定时获取服务端权威视图及版本，不自动重放事件。Live Counter 提供 Refresh state 按钮。实例过期后需重新挂载，尚未实现自动重连及服务端推送。
