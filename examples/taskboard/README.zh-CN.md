# Loom Taskboard

[English](README.md) · **简体中文**

本地单用户 SQLite 示例，串联路由、HTML、表单、模型校验、迁移与持久化。

```sh
racket examples/taskboard/app.rkt
```

打开 http://127.0.0.1:8080/。默认数据库为 `taskboard.db`，可通过 `LOOM_TASKBOARD_DB` 指定文件，使用 `LOOM_TASKBOARD_PORT` 修改端口。Linux 下可执行 `bash examples/taskboard/smoke.sh` 进行 HTTP 验收（需要 curl、Python 3）。

仅供本地演示，不适合多用户生产部署。进程级表单令牌不是会话绑定的 CSRF 实现，尚无认证、授权、生产传输限制和并发迁移支持。
