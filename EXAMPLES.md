# EXAMPLES.md（完整中文翻译版）

# 示例

通过真实世界的代码案例展示四项原则。每个示例都会说明 LLM 常见的错误做法，以及正确的改进方式。

---

# 1. 编码前先思考（Think Before Coding）

## 示例 1：隐藏假设（Hidden Assumptions）

**用户请求：**

> “添加一个导出用户数据的功能”

### ❌ LLM 常见做法（错误的假设）

```python
def export_users(format='json'):
    """Export all users to a file."""
    users = User.query.all()

    if format == 'json':
        with open('users.json', 'w') as f:
            json.dump([u.to_dict() for u in users], f)
    elif format == 'csv':
        with open('users.csv', 'w') as f:
            writer = csv.DictWriter(
                f,
                fieldnames=['id', 'email', 'name']
            )
            writer.writeheader()
            writer.writerows([u.to_dict() for u in users])

    return f"Exported {len(users)} users"
```

### 存在的问题

- 默认导出全部用户（是否需要分页？是否涉及隐私问题？）
- 默认决定文件保存位置
- 默认决定导出的字段
- 默认决定 CSV 字段结构
- 未确认实际业务需求

### ✅ 正确做法（主动暴露假设）

在实现前应先澄清：

```text
在开始实现之前，我需要确认以下问题：

1. 范围：导出全部用户还是部分用户？
   （涉及隐私与数据规模问题）

2. 导出方式：
   - 浏览器下载文件
   - 后台任务生成文件后邮件通知
   - API 接口返回数据

3. 导出字段：
   需要包含哪些字段？
   某些字段可能属于敏感信息。

4. 数据量：
   通常有多少用户？
   这会影响具体实现方案。

最简单的方案是：
提供一个返回分页 JSON 数据的 API。

如果需要文件导出，则需要更多信息。
```

---

## 示例 2：多种解释可能（Multiple Interpretations）

**用户请求：**

> “让搜索更快”

### ❌ LLM 常见做法（擅自选择方案）

```python
@lru_cache(maxsize=1000)
async def search(query: str):
    ...
```

直接增加：

- 缓存
- 数据库索引
- 异步处理

但没有确认“更快”究竟指什么。

### ✅ 正确做法

应先澄清目标：

```text
“让搜索更快”可能有多种含义：

1. 响应时间更短
   （500ms → 100ms）
   方案：索引、缓存

2. 并发能力更强
   （吞吐量提升）
   方案：异步处理、连接池

3. 用户感知更快
   （体验优化）
   方案：渐进加载、先显示部分结果

当前平均响应时间约为 500ms。

请问您最关注哪一方面？
```

---

# 2. 简洁优先（Simplicity First）

## 示例 1：过度抽象（Over-abstraction）

**用户请求：**

> “增加一个计算折扣的函数”

### ❌ LLM 常见做法（过度设计）

为了一个简单折扣计算，构建：

- Strategy 模式
- 抽象基类
- 配置对象
- 多种折扣策略
- 独立计算器类

最终需要三十多行配置代码才能完成一次简单计算。

### ✅ 正确做法（保持简单）

```python
def calculate_discount(amount: float, percent: float) -> float:
    """计算折扣金额，percent 范围为 0-100。"""
    return amount * (percent / 100)
```

使用方式：

```python
discount = calculate_discount(100.0, 10.0)
```

结果：

```text
10 元折扣
```

### 何时增加复杂度？

仅当真正出现以下需求时：

- 固定金额折扣
- 满减折扣
- 多种促销规则

届时再重构。

不要提前设计。

---

## 示例 2：推测性功能（Speculative Features）

**用户请求：**

> “把用户偏好保存到数据库”

### ❌ LLM 常见做法

额外加入：

- 缓存系统
- 校验器
- 自动合并逻辑
- 通知系统
- 可选参数

虽然技术上合理，但用户根本没有要求。

### ✅ 正确做法

```python
def save_preferences(db, user_id: int, preferences: dict):
    """保存用户偏好到数据库"""
    db.execute(
        "UPDATE users SET preferences = ? WHERE id = ?",
        (json.dumps(preferences), user_id)
    )
```

### 原则

后续真正需要时再增加：

- 缓存
- 数据校验
- 自动合并
- 消息通知

不要提前实现未来需求。

---

# 3. 外科手术式修改（Surgical Changes）

## 示例 1：顺手重构（Drive-by Refactoring）

**用户请求：**

> “修复空邮箱导致校验器崩溃的问题”

### ❌ LLM 常见做法

在修复 Bug 时同时：

- 改进邮箱校验规则
- 新增用户名规则
- 修改注释
- 添加 Docstring
- 调整代码结构

### 存在的问题

这些修改与当前 Bug 无关。

扩大了变更范围。

增加了引入新 Bug 的风险。

### ✅ 正确做法

仅修改导致问题的代码：

```diff
- if not user_data.get('email'):
+ email = user_data.get('email', '')
+ if not email or not email.strip():
```

以及：

```diff
- if '@' not in user_data['email']:
+ if '@' not in email:
```

除此之外不做任何修改。

### 原则

> 每一行修改都应直接对应用户需求。

---

## 示例 2：风格漂移（Style Drift）

**用户请求：**

> “给上传函数增加日志”

### ❌ LLM 常见做法

同时修改：

- 引号风格
- 类型标注
- Docstring
- 格式化方式
- 返回逻辑

虽然代码变“现代化”了，但这些都不是当前任务。

### ✅ 正确做法

只增加日志：

```python
logger.info(...)
logger.error(...)
logger.exception(...)
```

其余部分保持原样。

### 原则

遵循项目现有风格。

不要借修 Bug 或加功能的机会进行重构。

---

# 4. 以目标驱动执行（Goal-Driven Execution）

## 示例 1：模糊目标 vs 可验证目标

**用户请求：**

> “修复认证系统”

### ❌ LLM 常见做法

```text
1. 查看代码
2. 找出问题
3. 做一些优化
4. 测试
```

问题：

没有成功标准。

无法判断任务是否完成。

### ✅ 正确做法

首先明确问题：

例如：

> 用户修改密码后旧会话依然有效

然后制定可验证计划：

```text
1. 编写测试
   验证旧会话未失效

2. 运行测试
   确认失败
   （复现 Bug）

3. 修改代码
   密码变更后使旧会话失效

4. 再次运行测试
   确认通过

5. 运行完整认证测试
   确认无回归问题
```

---

## 示例 2：多步骤验证

**用户请求：**

> “为 API 增加限流”

### ❌ LLM 常见做法

一次性实现：

- Redis
- 多策略支持
- 配置中心
- 监控系统

提交一个数百行的超大改动。

### ✅ 正确做法

逐步推进：

#### 第一步

增加内存限流。

验证：

```text
100 次请求
前 10 次成功
其余返回 429
```

#### 第二步

提取为中间件。

验证：

```text
多个接口均生效
```

#### 第三步

增加 Redis 支持。

验证：

```text
多实例共享计数器
```

#### 第四步

增加配置化。

验证：

```text
不同接口支持不同限额
```

每一步都可以：

- 单独测试
- 单独部署
- 单独回滚

---

## 示例 3：测试优先验证

**用户请求：**

> “存在重复分数时排序会出错”

### ❌ LLM 常见做法

直接修改排序逻辑。

没有确认问题是否真实存在。

没有验证修改是否有效。

### ✅ 正确做法

第一步：编写测试。

```python
def test_sort_with_duplicate_scores():
    ...
```

验证：

```text
测试失败
成功复现 Bug
```

第二步：修复代码。

```python
def sort_scores(scores):
    return sorted(
        scores,
        key=lambda x: (-x['score'], x['name'])
    )
```

第三步：再次验证。

```text
测试通过
排序结果稳定
```

---

# 反模式总结

| 原则 | 反模式 | 正确做法 |
|--------|--------|--------|
| 编码前先思考 | 默默做假设 | 显式列出假设并确认 |
| 简洁优先 | 为简单需求设计复杂架构 | 先使用最简单方案 |
| 外科手术式修改 | 修 Bug 时顺手重构 | 只修改必要代码 |
| 目标驱动执行 | “我来优化一下代码” | 编写测试 → 修复 → 验证 |

---

# 核心洞察（Key Insight）

这些复杂实现并非完全错误。

它们的问题在于：

**复杂度出现得太早。**

其后果包括：

- 代码更难理解
- Bug 更多
- 实现时间更长
- 测试更困难

而简单实现通常：

- 更容易理解
- 更容易维护
- 更容易测试
- 更容易交付

并且在未来真正需要复杂度时，依然可以逐步重构。

## 最终原则

**优秀代码并不是提前解决未来的问题。**

**优秀代码是在今天，用最简单的方式解决今天的问题。**
