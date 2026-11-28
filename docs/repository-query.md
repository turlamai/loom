# Repository queries / 仓储查询

`repository-find` accepts `#:where` (a symbol-keyed hash of equality filters), `#:order-by`, `#:descending?`, `#:limit` (1–1000), and `#:offset`. Filters are combined with AND; SQL NULL is expressed using `sql-null` from `db` for optional fields. Field names and values are validated against the model; values are bound parameters. Ordering uses the primary key as a tie breaker. NULL ordering and collation depend on the database. `repository-count` accepts the same filters without pagination. Applications must enforce authorization separately.

`repository-find` 支持等值条件组合、排序及分页，`repository-count` 支持条件计数。通过 `db` 的 `sql-null` 查询可选字段的空值，布尔值 `#f` 不代表 NULL。字段和参数均经过模型校验，查询参数绑定，不拼接用户输入。排序以主键消除并列歧义，NULL 排序和字符排序规则由数据库决定。应用仍须独立实现访问授权。
