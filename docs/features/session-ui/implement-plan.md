# Sigma Session UI & Observability V2 — Implementation Plan

- 版本：1.0
- 日期：2026-09-09
- 配套需求：`prd.md`；需求与口径以 PRD 为准。
- 状态：P0（SUI-00～09、11、12）已实施并验证；可选 SUI-10 deferred。完成证据见 `implementation-report.md`。
- 目标读者：负责调度、实现和验收的 Codex / 其他 coding agents。
- 建议仓库位置：`docs/features/session-ui-observability-v2/`。

## 1. 执行原则

先核对源码与冻结契约，再并行实现采集、持久化和纯展示，最后接入 runtime、LiveView 与受控操作。不要先在 `SessionLive` 堆统计字段，再补数据语义。

本计划以上一轮审查证据为基线：搜索曾命中 `e59e49a298e66a7c571cec2e7878ae85b082f8b0`，文件读取为当时 `main`，未确认全部来自同一提交。本轮源码重读受访问限制。第一任务必须记录当前 HEAD 并核对差异；源码已有功能应复用，不能重复搭建。

所有 worker 开始前读取当前仓库 `AGENTS.md` 和相应目录指令。保持 Elixir/OTP 的既有边界，优先纯函数、不可变事件与受监督进程。继续使用 DuskMoon。禁止引入新的数据库、第二套前端框架或跨项目大规模重构。

### 1.1 不可违反的约束

- Session spend、active context、fork inherited history 是不同统计，不能互相代替。
- Provider usage 细分不重复相加；未知不是零；平均速度按同一请求集合加权。
- Durable journal 是累计事实来源；LiveView 与内存 debug logs 不是。
- Retry 不能只是给当前 leaf 再发一次旧 prompt；Fork/Retry 不能声称会回滚文件。
- 新操作必须经过 runtime admission、busy guard、revision 检查与幂等边界。
- 新 metrics entry 不进入模型上下文，也不能破坏 active-leaf 语义。
- 不根据历史 note 的“测试通过”记录宣称本次验证成功。

## 2. 交付阶段与完成门槛

| 阶段 | 结果 | 门槛 |
| --- | --- | --- |
| A：契约与事实 | 身份、usage、时间、journal、projection 契约可测试 | SUI-00～03 完成；纯 reducer 与 adapter fixtures 通过。 |
| B：可观察会话 | Runtime snapshot、context/compaction、footer、右栏、稳定恢复 | SUI-04～07 完成；先支持正确观测，再谈操作升级。 |
| C：安全交互 | 真正的 Retry、Fork、busy/conflict/idempotency 与副作用提示 | SUI-08～09 完成；不能用 Resend 代替此阶段。 |
| D：发布验收 | 跨层测试、兼容性、浏览器验证、操作文档 | SUI-11～12 完成，PRD AC-01～17 全部覆盖。 |
| E：可选增强 | Inspector、详细历史和压缩轮数预测 | SUI-10，可独立发布；不得改变核心统计和压缩决策。 |

A、B 可以作为内部中间版本，但只有 C、D 通过后才能标记 PRD 中的必需 V2 功能完成。SUI-10 不阻塞正式基础版本。

## 3. 依赖与可并行分工

| 任务 | 优先级 | 依赖 | 主责任边界 |
| --- | --- | --- | --- |
| SUI-00 基线与契约冻结 | P0 | 无 | 当前源码、契约文档、fixture 清单 |
| SUI-01 共享模型与纯 projection | P0 | 00 | `sigma_protocol` DTO；`sigma_session` 纯 reducer |
| SUI-02 Provider / tool 采集 | P0 | 01 | `sigma_ai` adapters；现有 tool dispatcher 接缝 |
| SUI-03 Journal 持久化与恢复 | P0 | 01 | `sigma_session` writer/encoder/log/replay |
| SUI-04 Runtime snapshot / protocol | P0 | 02、03 | `sigma_agent` 生命周期、订阅、PublicRuntime |
| SUI-05 Context / compaction | P0 | 01、03 | Runtime context/policy 与 compaction 接缝 |
| SUI-06 UI 组件与布局 | P0 | 01 | 无业务 I/O 的 DuskMoon 展示组件 |
| SUI-07 LiveView 接入 | P0 | 04、05、06 | `SessionLive` 的唯一整合者 |
| SUI-08 Retry / Fork operation | P0 | 03、04 | Runtime + Session operations |
| SUI-09 操作 UI 与分支展示 | P0 | 07、08 | Message/turn actions、popover、冲突反馈 |
| SUI-10 Inspector / 预测 | P1 | 05、07 | 独立 drawer 与只读历史查询 |
| SUI-11 跨层验收与回归 | P0 | 各任务持续提供测试；最终等待 07、09 | Test fixtures、浏览器、兼容与性能验证 |
| SUI-12 文档与发布验收 | P0 | 07、09、11 | 使用文档、迁移说明、完成报告 |

推荐第一并行波：SUI-02、SUI-03、SUI-06。第二波：SUI-04 与 SUI-05 在冻结的接缝上并行，测试 worker 同时准备 SUI-11。第三波：SUI-07 与 SUI-08。第四波：SUI-09、可选 SUI-10、SUI-11 最终验证。

### 3.1 共享文件的修改所有权

`session_live.ex` 由 SUI-07 的整合者集中修改；SUI-06 在独立组件文件交付，不直接改大段主 render。SUI-09 在 SUI-07 合并后接入 actions。SUI-10 通过已冻结的组件入口扩展，不与整合者争抢同一区域。

`sigma_agent.ex` 的运行路径由 SUI-04 整合者集中修改。SUI-02 提供独立采集 helper 与 adapter 改动；SUI-05 提供 context/policy helper 与需要插入的明确调用点。无法避开的相同行改动必须串行合并。

`writer.ex`、`entry_encoder.ex`、`log.ex` 的新记录格式由 SUI-03 持有；SUI-05 和 SUI-08 使用已冻结的接口，不另定义第二种 journal 格式。协议类型与版本集合由 SUI-01/SUI-04 协调，禁止多个 worker 各自增加不一致事件名。

## 4. 冻结的逻辑合同

以下是交付合同，不是已有 API 声明。具体模块、函数和正式事件名由 SUI-00 对照仓库确定。

### 4.1 Request / Turn 身份与事实

Request 必须携带 `request_id`、`turn_id`（辅助调用允许独立关联）、稳定 origin session 身份、provider/model、purpose、状态、started/finished 时间、有效时长、usage/provenance/revision。

Turn 必须携带原始 user entry/checkpoint、执行身份、状态及终止原因；retry 通过 `retry_of_turn_id` 建立关系，不覆盖旧 turn。Transport retry 是新 request，不是新用户 turn。

Metrics 更新由单调 journal sequence / revision 排序，并有去重身份。Usage correction 更新原 request 的贡献值，不作为新增收费请求。所有 request 聚合都必须保留 source ownership，以正确处理 fork。

### 4.2 Projection 与 snapshot

建议 projection 包含：session own usage、coverage、按 purpose/model 的分组、turn summaries、request summaries、成功 compaction 记录、当前 active lineage 引用。所有累计值可从 durable facts 重建。

Runtime snapshot 另外携带当前 execution phase、active turn/request、ContextSnapshot、effective compaction policy、snapshot watermark 与 freshness。不要把不可重建的瞬时 UI 状态当成 durable metrics。

### 4.3 默认指标口径

完整总量是 canonical input total + output total，cache/reasoning 作为已包含的细分展示。部分数据显式标记。

默认 LLM tok/s 是 output total / provider request elapsed。Session / turn 平均为匹配请求的总 output 除以总 request elapsed，包括请求等待，不含请求之外的工具/审批时间。纯生成速度单独命名，仅在 numerator 和窗口可对齐时提供。

UTC 时间用于显示，monotonic 差值用于同进程计时。未知值、legacy 值和不完整覆盖在 schema 中保留，不能靠 UI 临时猜测。

### 4.4 Context / compaction 合同

分别输出最近实际 input 与下一请求估计；携带 context revision、模型与来源。Effective policy 来自 runtime，前端不计算 80% fallback。

Compaction 的成功事实必须引用真正提交的 context entry；仅 start 或 LLM summary 生成成功不算完成。压缩成本按 request purpose 计入总消耗，失败也保留已知成本。

### 4.5 操作合同

Retry/Fork 输入至少可表达 source session、明确的安全 checkpoint、expected revision/leaf、operation ID；输出明确 accepted / busy / conflict / invalid boundary / missing history 等结果，不能只有 boolean。

Fork 发布必须保留来源关系且不自动执行模型；Retry 必须原子确定分支与执行接纳。网络超时后的查询/重复提交应能够找到原 operation 结果，而不是重新执行。

## 5. 工作单

### SUI-00 — 核对当前 HEAD，冻结 schema 与实施接缝

**目标：** 建立可验证基线，避免沿用过时结论；消除会阻塞并行开发的歧义。

**读取范围：** 当前 `AGENTS.md`；`apps/sigma_web/lib/sigma_web/live/session_live.ex`；`apps/sigma_agent/lib/sigma_agent.ex`、`session_process.ex`、Runtime/PublicRuntime/TurnState 相关实现；session writer/log/entry encoder/operations；provider event/usage；实际协议文档和 schema；DuskMoon chat actions slot 与前端 hooks。

**必须核对：** 当前 context 是否仍使用历史最大值；compaction 历史恢复；Retry 的具体动作位置与语义；tool/request/turn ID；模型窗口元数据来源；rename/fork 是否改变 session 身份；特殊 journal entry 的 active-leaf 行为；协议对未知类型的处理；实际 composer 发送快捷键。

**交付：** 一份简短 `contract.md` 与 fixture 清单，记录 HEAD、关键符号/行号、已实现/缺失表、schema owner、模块依赖图、增量协议兼容策略及每个共享文件的整合者。若前一轮判断已过时，写明差异并删除重复任务。

**验收：** 所有 worker 能基于相同的 versioned fixtures 工作；无 provider 字段映射、metrics entry 语义、session ownership 或 retry checkpoint 的隐含假设。不能在 unresolved journal/protocol 兼容决策上直接进入编码。

**不做：** 全仓库重构、UI 大改、运行未授权的远程写操作。

### SUI-01 — 共享 DTO、数值规则与纯 metrics reducer

**目标：** 在无 provider、无 LiveView、无磁盘的测试中证明统计正确。

**建议文件边界：** 共享 DTO 放在 `sigma_protocol`；纯 reducer 放在 `sigma_session` 的独立 metrics 模块。实际路径遵循 SUI-00 冻结结果。Reducer 不依赖 runtime GenServer 或 Web。

**实施内容：** 实现 request identity/revision 去重、usage normalization 后的聚合、own/inherited/active-lineage scope、weighted throughput、coverage、失败/取消事实、compaction committed 去重、legacy unknown 数据质量。支持同一 request 最终 correction 替换之前贡献。

**Fixtures：** 单 turn 多请求；40k input 包含 30k cache、1k output 包含 400 reasoning；10 tokens/0.1s 与 1000/20s；重复 terminal；迟到 correction；fork 继承；旧 branch 消耗；usage 缺失；零输出/零时间。

**验收：** 对相同 canonical facts 的完整 replay 与增量 fold 得出相同 snapshot；对重复送达不重复累计；所有 unknown 明确保留；不出现负总量、NaN、Infinity 或不安全原子创建。

**交付：** DTO、纯函数、fixture、单元测试、字段说明；不接入 Web 或新增数据库。

### SUI-02 — Provider 请求与工具执行的可计量事实

**目标：** 在正确执行边界采集事实，不能用浏览器文本渲染速度代替模型速度。

**文件边界：** 当前 `sigma_ai` provider adapters、`ProviderEvent` 及流式归一化接缝；现有 tool dispatcher 的 begin/end/error 接缝。对 `sigma_agent.ex` 的调用点由 SUI-04 整合。

**实施内容：** 为实际 provider attempt 分配稳定 request ID；采集开始、首有效输出、首可见文本、terminal、时长；映射 canonical usage 及原始含义。捕获主对话、压缩、MCP sampling/其他辅助路径中确实存在的 LLM 调用，不能只 instrument 最后一个 assistant response。

**重试与取消：** 可见 transport retry 各自计量，保留 retry 关系；调用取消后迟到的最终 usage 仍可校正原 request，但不得恢复 cancelled turn。无法观察到的 proxy 内部行为不伪造记录。

**工具：** 记录 tool ID、turn/request 关联、duration、status；并行工具的累计时间不等于墙钟时间。工具返回内容不直接混进 metrics，也不记录敏感认证信息。

**验收：** Mock streaming provider 验证 text、thinking、tool-only、usage-only terminal、keepalive、网络错误、取消、无 usage 和不同原始计数结构。计时来自 monotonic clock。默认 tok/s 包括请求等待但不含外部工具耗时。

**交付：** Adapter/helper 变更、映射说明、mock fixtures 和 focused tests。不得同时重写 provider 协议解析器。

### SUI-03 — Journal 持久化、replay 与跨 fork ownership

**目标：** 刷新、压缩、分支切换与 runtime 重启后，累计统计仍有可靠来源。

**文件边界：** `apps/sigma_session/lib/sigma_session/writer.ex`、`entry_encoder.ex`、`log.ex` 及现有 replay/snapshot 实现。

**实施内容：** 按冻结的格式持久化必要 operational facts，保留 sequence、request revision、origin 和关联 context entry。请求 start/terminal/correction 都具备明确恢复语义；不要写入每个 token delta。

**关键限制：** Operational record 不成为 LLM message，不意外移动 conversation active leaf。Session spend 不能从仅含当前有效上下文的 messages snapshot 重建。新 fork 的 inherited facts 保留原 request 身份，新执行归属新 session。

**持久化边界：** 已向客户端确认的最终事实必须可 replay；Writer 失败不能悄悄返回完整成功。对远程 provider 已执行但本地 terminal 未持久化的情况记录 interrupted/unknown，不承诺不存在的 exactly-once 远程调用。

**恢复：** 读取旧日志不自动改写它；必要的新身份或版本元数据只按显式、兼容的写入路径引入。检查 rename、export、fork、compact 和旧 reader 行为。

**验收：** JSONL round-trip；截断/异常记录按既有规则处理；重复 facts；跨进程重启；compaction 前后历史；旧分支；fork 后父/子 usage；rename 后 ownership 不变化。统计 entry 不改变送给 provider 的上下文。

**交付：** Writer/encoder/replay 变更、兼容 fixture、契约更新、完整持久化测试。

### SUI-04 — Runtime live projection、一致性 snapshot 与协议接入

**目标：** Web、CLI 与其他客户端读取相同状态，不由各客户端独立猜测。

**文件边界：** `SessionProcess`、现有 `Runtime`、`PublicRuntime`、subscription/relay、`sigma_protocol` 闭合 schema；`sigma_agent.ex` 由本任务整合。

**实施内容：** 接入 SUI-02 facts 与 SUI-03 writer；live projection 跟随已接受的事实更新。初始化先恢复 durable metrics，再接上当前活动 turn。返回 session/turn/request summaries、runtime phase、snapshot watermark；不能把 mount 时默认 false 当成真实 idle。

**协议：** 实现经批准命名的 metrics snapshot 查询和更新；审查旧客户端对未知类型的处理，采用显式能力协商或明确版本边界。复用现有 PublicRuntime/socket/stdio，不新建第二套控制面。

**一致性：** 解决 subscribe/snapshot 竞态；增量具有 cursor/sequence，缺口要求 resync。限制高频更新；最终事实保持可恢复。不要将每秒相对时间刷新变成 server 全量 replay。

**验收：** 两个客户端同时查看同一 turn 得到一致终态；刷新正在运行的 turn 正确恢复；慢消费者和丢失增量后 resync；重复事件去重；partial usage 和迟到 correction 更新正确；浏览器断开不影响 agent。

**交付：** Runtime/query 接口、协议契约、subscription 测试、状态恢复测试；正式 schema 不暴露 PID、ref、secret 或内部进程项。

### SUI-05 — 当前 context 与 compaction 生命周期

**目标：** 解决“context 只增不减”和“压缩次数仅在内存中”的问题，并统一预算来源。

**文件边界：** 现有 context builder、compaction policy/runtime helper；使用 SUI-03 writer 接口。`sigma_agent.ex` 插入点交 SUI-04 整合。

**实施内容：** 生成带 revision 的 ContextSnapshot；区分 last measured request input 与 next-request estimate；汇总系统指令、工具 schema、skills、附件等实际组装来源。估算器未覆盖的内容需要标注，不要假装是精确 tokenizer 结果。

**Policy：** 输出有效 threshold、window source、check phase 和 overflow 状态；保持已确认的 runtime 既有策略，不在 UI 复制公式。确认发请求前的 hard-budget 检查和 output reserve；不能依靠上一轮结束后的 compaction 避免所有超窗问题。

**Compaction：** Instrument start/commit/failure、关联 LLM request 和 summary/context entry。成功计数以实际提交的 context entry 为准，跨重启可重建。发生模型或 active leaf 变化时使旧 estimate 失效。支持安全的手动 Compact operation；尚无安全入口时先补 operation，不从 Web 直接删消息。

**验收：** 100k → 25k 的 context 降低；累计 spend 不消失；压缩 LLM usage 被记录；失败不增加成功次数；压缩后的 stale usage 不覆盖新 epoch；模型 window 未知；换更小模型触发明确预算反馈；手动操作 busy guard。

**交付：** ContextSnapshot、policy view、compaction facts/replay、上述测试。预测轮数留给 SUI-10。

### SUI-06 — 纯展示组件与布局重整

**目标：** 在 runtime 尚未接好时，使用冻结的 fixture 完成可验收的 UI 组件。

**文件边界：** `sigma_web` 独立 session components、必要 CSS/hooks。不要与 SUI-07 同时改 `SessionLive` 主文件。

**组件：** MessageMetricsFooter、TurnSummary、SessionOverviewRail、ContextBudgetCard、CompactionSummary、TurnStatus、只呈现状态的 ActionBar。名称为建议，可遵循现有风格调整。

**实施内容：** Compact 默认信息，详情展开；所有 unknown/partial/legacy/streaming/failed/cancelled 状态都有样式。中性 surface 与语义状态色；长代码局部滚动；工作目录等元数据折叠；右栏在窄屏变 drawer。

**交互要求：** 行为按钮可键盘/触屏访问，不仅 hover；elapsed/relative-time 显示不抖动；Composer 高度和快捷键说明一致；统计更新不重置输入/滚动。

**验收：** 对同一组 fixture 检查 390/1024/1440 宽度、light/dark、长标题/路径、0/unknown/大数字、长代码和工具错误；检查 DuskMoon actions slot 与 LiveView patch 的兼容性。仅 SSR 测试不能证明 web component 的实际行为。

**交付：** 组件、格式化函数、组件测试与浏览器截图。无 provider、journal 或 Runtime I/O。

### SUI-07 — SessionLive 接入与基础 observability 完成

**目标：** 把真实 snapshot/updates 接入组件，形成可用的右栏和聊天 footer。

**文件边界：** `apps/sigma_web/lib/sigma_web/live/session_live.ex` 及相关 LiveView tests；本任务持有主文件修改权。

**实施内容：** 替换当前的历史 max context 推导；不再在 Web 重复计算 usage 总数、速度或阈值。载入真实 session started_at、usage coverage、turn/request summaries 和 compaction summary。流式结束、后台辅助请求和 source leaf 改变都更新对应状态。

**基础视图：** 每条 assistant 的 request metrics、完整 turn 合计、右栏 own usage/平均速度/时间/context、最后压缩详情；多模型与 inherited 状态可解释。旧数据保持可查看。

**现有操作：** 在 SUI-09 完成前，将仍然只是重发的旧动作准确标为 Resend，不能提前展示假 Retry。既有 Fork 按当前受控接口运行，不绕开 busy guard。

**验收：** LiveView refresh 不把正在运行 session 误判为空闲；模型切换后 context invalidation 正确；无 usage 时非假零；不会在每个 token/时间 tick 扫描日志；输入、滚动和展开状态稳定。

**交付：** 已接入的聊天页、关键 LiveView tests、更新前后截图与仍未接入能力清单。

### SUI-08 — 分支感知 Retry 与安全 Fork runtime

**目标：** 让操作语义与 UI 文案一致，并在服务端保证幂等和边界安全。

**文件边界：** 既有 `Sigma.Session.Operations`、journal branch/checkpoint 读取与 `Sigma.Agent.Runtime/PublicRuntime` 操作。复用 fork 的既有原子发布机制，不重建整个 session storage。

**Retry：** 解析 selected turn 的原始 user input 与执行 checkpoint；创建新替代分支与新 turn ID；关联 retry_of；保留所有旧分支及其 usage。不会携带原回答后面的对话；不会隐式改成当前 leaf resend。恢复保存的附件和已物化输入，无法恢复则明确拒绝。

**Fork：** 从安全的已持久化 turn 边界创建目标 session；保留 source relation；默认不触发模型。源 session 保持不变，新 own spend 为零。拒绝孤立 tool-call/tool-result 的非法上下文。

**并发：** Operation ID 幂等；expected source revision/leaf 检查；busy、等待权限、compacting、cancelling 状态受统一 admission 管理。记录可供重连查询的操作结果，避免“请求超时但已成功”导致重复创建。

**副作用：** 不执行 Git reset、checkout、文件恢复或外部补偿。当前权限策略生效；原 provider/model 不可用时返回需选择结果，不静默更换。

**验收：** 重试第一轮/历史轮/压缩前轮；附件缺失；旧 journal 缺乏 checkpoint；在工具中间 fork；重复 operation；同源多标签页竞争；源 busy；发布失败；rename 后来源可定位；原文件保持当前内容且分支历史未被删除。

**交付：** Operation contract、实现、原子性/幂等/失败恢复 tests。不能仅凭 UI 测试证明动作正确。

### SUI-09 — Retry/Fork UI、冲突与替代分支展示

**目标：** 让用户在执行前知道从哪里开始、会创建什么、哪些东西不会回滚。

**文件边界：** SUI-07 合并后的 session actions 接缝、独立 popover/dialog 与对应 hooks；不重写 runtime operation。

**实施内容：** Retry turn、Resend as new turn、Fork here 明确分开；Fork 显示 source turn、目标标题、模型、共享工作目录和切换选项。Retry 提示副作用不会回滚，显示原模型或显式替代选择。

**状态：** 从 server snapshot 决定按钮可用性；submitted/accepted/in-flight 不重复发送。对 busy、revision conflict、missing attachment/history、invalid boundary 提供具体原因及安全选择。取消后等 terminal 再允许重试。

**分支展示：** 原回答与新回答作为可查看的替代执行；至少能够查看两者与其来源，不要求完整树形编辑器。Fork 成功提供跳转，源 session 保持可返回。

**验收：** 键盘、触屏、双击、重连、多标签页；Retry 不落到当前 tail；fork 默认不调用模型；用户无法绕过确认误以为文件已回滚；服务端拒绝时草稿不丢失。

**交付：** Action UI、浏览器交互测试/截图、操作文案与错误状态矩阵。

### SUI-10 — 可选 Inspector 与压缩轮数预测

**目标：** 提供更深观察能力，但不阻塞基础 V2，也不改变执行逻辑。

**文件边界：** 独立 drawer/只读查询模块，复用现有 summaries；通过 SUI-07 的扩展入口接入。

**实施内容：** 分页查看 requests、tools、compactions 和 branches；显示每条记录的数据来源、usage coverage、before/after 与 summary。只导出经过选择和脱敏的字段。

**预测：** 仅在同模型/策略/context epoch 下有足够有效 turn 增长样本时，显示低置信度轮数区间。可采用最近样本 EWMA，参数写入说明并有测试；压缩、模型/工具变化或异常增长后重置。不显示分钟倒计时，不参与 admission/compaction 决策。

**验收：** 缺少 timing 或 summary 的旧记录仍可读；大量历史分页不拖慢输入；无效样本不输出看似精确的 ETA；snapshot 和实际 runtime 行为不受预测影响。

**交付：** 可独立关闭的增强 UI、查询与测试。未实现时在发布记录中标为 deferred，不冒充必需功能缺陷。

### SUI-11 — 跨层验证、兼容性与性能回归

**目标：** 证明 provider → journal → runtime → UI 的整个链路正确，而不是只验证局部组件。

**开始时间：** SUI-01 开始后即可准备 fixture 与测试 harness；最终集成验证等待 SUI-07、SUI-09。SUI-10 若纳入发布，追加其用例。

**测试层次：** 纯 reducer；adapter mock streams；writer/replay；runtime/protocol；LiveView；真实浏览器中的 DuskMoon web components。全部基础测试不依赖付费模型。

**大数据：** 至少构造 10,000 条 journal records，含旧分支、compaction、失败/辅助 requests；验证 totals、分页、steady-state 增量更新和内存趋势。检查每次 render/tick 没有全量扫描，不以单次快照截图代替性能验证。

**恢复与竞态：** Inject duplicate、gap、late correction、writer failure、disconnect、runtime restart 和 operation timeout。验证 terminal 事实可恢复、未知消耗明确、不会意外再次调用 provider。

**浏览器：** 三种宽度、两种主题；长 markdown/code、工具折叠、旧日志、usage 缺失、failure/cancellation、相对时间、输入保留、滚动不抢占、actions keyboard/focus。

**验收：** PRD AC-01～17 有逐项证据；命令、退出状态、失败说明和截图可追溯。现有故障与新回归分开报告；绝不把未执行的测试写成通过。

### SUI-12 — 文档、发布门槛与交付报告

**目标：** 让使用者和后续 agent 理解指标、限制与安全边界。

**实施内容：** 更新使用文档、metrics/协议契约、旧日志兼容说明、Retry/Resend/Fork 语义、compaction 面板说明、scope 与 coverage 解释。保留本 PRD 和 plan 为长期参考，不为每个小函数创建流水账笔记。

**发布安全：** 新 UI 可以 feature flag 控制，但关闭 UI 不应删除 durable facts。新增 journal 格式的旧 binary 兼容能力由测试决定；若旧版本无法读取，明确最低兼容版本，不能承诺直接降级。

**交付报告：** 精确 HEAD；任务完成表；AC-01～17 证据；实际测试命令与退出结果；浏览器截图；未解决问题；schema/version 变化；deferred 的 SUI-10 内容。

**完成条件：** P0 全部通过，用户要求的指标和 Retry/Fork 均为真实能力；旧数据可读；最终报告没有未说明的未知状态或测试缺口。

## 6. 验收场景映射

| 场景 | 主要责任 | 对应 PRD |
| --- | --- | --- |
| 多 request 的 turn 汇总、重复投递去重 | 01、03、04、07 | AC-01、10 |
| Cache/reasoning 不重复、partial usage | 01、02、07 | AC-02、11 |
| 加权吞吐率与工具时间隔离 | 01、02 | AC-03、04 |
| Context 压缩后下降、未知窗口、模型切换 | 05、07 | AC-05、12 |
| 重启恢复 compaction/usage、legacy data | 03、04、05 | AC-06 |
| Fork ownership、父子会话互不重计 | 01、03、08、09 | AC-07 |
| Retry 真正从旧 checkpoint 执行 | 08、09 | AC-08 |
| 文件不回滚、共享目录警告 | 08、09 | AC-09 |
| Cancel/error/interrupted/late correction | 02、03、04、07 | AC-10、11 |
| Subscribe/snapshot 竞态与 resync | 04、07 | AC-13 |
| 浏览器、主题、键盘、输入和滚动 | 06、07、09、11 | AC-14 |
| 10k records、增量行为、无 token 级写放大 | 03、04、07、11 | AC-15 |
| 压缩失败及安全手动压缩 | 03、05、07 | AC-16 |
| 非 context journal records 与旧协议兼容 | 00、01、03、04、11 | AC-17 |

## 7. 验证命令与证据规范

先按当前 `AGENTS.md` 和锁文件建立环境。以下是预期验证入口，不是已经执行过的命令；SUI-00 需要确认当前仓库 alias、前端测试脚本和依赖要求。

| 范围 | 预期入口 |
| --- | --- |
| 格式 | `mix format --check-formatted` |
| 编译 | `mix compile --warnings-as-errors` |
| Provider | `mix test apps/sigma_ai/test` |
| Shared protocol | `mix test apps/sigma_protocol/test` |
| Journal / projection | `mix test apps/sigma_session/test` |
| Runtime | `mix test apps/sigma_agent/test` |
| Web | `mix test apps/sigma_web/test` |
| 资产 | 当前仓库支持时运行 `mix assets.build` |
| 最终回归 | `mix test` 加当前仓库真实浏览器测试入口 |

Focused tests 应先运行新测试文件，再运行所属 app，最后进行 umbrella 回归。不要为掩盖失败删除原测试、跳过断言或引入真实 provider key。真实模型 smoke test 仅在用户授权且可控的情况下额外运行，不能代替 mocks。

每个 work order 的结束报告只需：改动范围、实现的合同、实际测试与结果、已知限制、需要整合的接口。不要重复复述全仓库背景或产生一串无长期价值的 Agent Note 流水账。

## 8. Codex 启动工作指令

从 SUI-00 开始，读取本 PRD、计划和当前仓库指令，记录 HEAD 并核对已有实现。先冻结身份、usage、时间、journal operational records、protocol compatibility 和 Retry/Fork checkpoint 契约。

完成 SUI-01 后，按 SUI-02 / SUI-03 / SUI-06 分配互不冲突的并行任务。共享文件由指定整合者修改，worker 不得各自改写同一大模块。

不要一口气重写聊天页。每个任务完成一个可验证合同并提交对应测试；先保证统计正确与重启恢复，再接 UI 和安全操作。发现仓库已实现某项需求时，以当前源码与测试为准调整计划，并记录差异。

只有 P0 任务和 AC-01～17 验证完成后，才能声明 Sigma Session UI & Observability V2 的基础范围完成。可选 Inspector/轮数预测单独报告状态。
