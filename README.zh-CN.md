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
