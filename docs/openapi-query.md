# Typed API queries / 类型化 API 查询参数

Declare a model with `define-model` and pass it as `#:query` to `api-operation`. The existing two-argument handler receives its JSON body unchanged; `(current-api-query)` returns a request-scoped immutable hash of converted query values. Supported scalar types are string, integer, boolean (`true` or `false`), and finite number. Required fields must be present; optional absent fields are omitted. Unknown and repeated parameters are rejected with HTTP 400. The declared schema generates OpenAPI query parameter entries. The parser accepts at most 128 decoded pairs and 4096 characters per value; upstream HTTP request limits remain necessary. Operations without a query model retain their existing behavior.

使用 `define-model` 定义查询参数，通过 `#:query` 注册到 API。处理器原有 JSON 参数保持不变，`(current-api-query)` 提供当前请求的类型转换结果。支持字符串、整数、布尔值及有限数值；拒绝缺失必填项、未知字段及重复字段。自动生成 OpenAPI 参数声明。限制解码后的参数数量及单值长度，仍需配置 HTTP 层请求限制。未声明查询模型的接口保持兼容。
